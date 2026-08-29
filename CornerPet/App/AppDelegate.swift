import AppKit
import Darwin
import SwiftUI

struct AppLaunchOptions: Equatable {
    let usesInMemoryStore: Bool
    let opensCapture: Bool
    let opensCaptureWithoutActivation: Bool
    let handlesCommandCommaSignal: Bool
    let usesDeleteFailureFixture: Bool
    let keepsCaptureOpen: Bool
    let showsReminder: Bool
    let reminderCorner: TriggerCorner?
    let languageOverride: AppLanguage?

    init(arguments: [String]) {
        let isUITesting = arguments.contains("--cornerpet-ui-testing")
        usesInMemoryStore = isUITesting
            && arguments.contains("--cornerpet-memory-store")
        opensCaptureWithoutActivation = isUITesting
            && arguments.contains("--cornerpet-ui-open-capture-without-activation")
        handlesCommandCommaSignal = isUITesting
            && arguments.contains("--cornerpet-ui-command-comma-signal")
        opensCapture = isUITesting
            && (arguments.contains("--cornerpet-open-capture") || opensCaptureWithoutActivation)
        usesDeleteFailureFixture = usesInMemoryStore
            && arguments.contains("--cornerpet-ui-delete-failure")
        keepsCaptureOpen = isUITesting
            && arguments.contains("--cornerpet-ui-keep-capture-open")
        showsReminder = usesInMemoryStore
            && arguments.contains("--cornerpet-ui-show-reminder")
        reminderCorner = if showsReminder,
            let rawValue = arguments.first(where: {
                $0.hasPrefix("--cornerpet-ui-reminder-corner=")
            })?.split(separator: "=", maxSplits: 1).last {
            TriggerCorner(rawValue: String(rawValue))
        } else {
            nil
        }
        languageOverride = if isUITesting,
            let rawValue = arguments.first(where: {
                $0.hasPrefix("--cornerpet-ui-language=")
            })?.split(separator: "=", maxSplits: 1).last {
            AppLanguage(rawValue: String(rawValue))
        } else {
            nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias PanelControllerFactory = () -> CapturePanelController
    typealias TriggerCoordinatorFactory = (CapturePanelController) -> CornerTriggerCoordinator
    typealias LifecycleCoordinatorFactory = (CapturePanelController) -> PanelLifecycleCoordinator
    typealias CompositionFactory = (CapturePanelController) throws -> (any CaptureComposing)?

    private let panelControllerFactory: PanelControllerFactory
    private let triggerCoordinatorFactory: TriggerCoordinatorFactory
    private let lifecycleCoordinatorFactory: LifecycleCoordinatorFactory
    private let compositionFactory: CompositionFactory
    private let launchOptions: AppLaunchOptions
    private let reminderStateStore: any ReminderStateStoring
    private var commandCommaSignalSource: (any DispatchSourceSignal)?

    let appSettings: AppSettings
    let launchAtLoginController: LaunchAtLoginController
    let screenCoordinator: ScreenCoordinator

    private(set) var panelController: CapturePanelController?
    private(set) var triggerCoordinator: CornerTriggerCoordinator?
    private(set) var lifecycleCoordinator: PanelLifecycleCoordinator?
    private(set) var composition: (any CaptureComposing)?
    private(set) var petReminderPanelController: PetReminderPanelController?
    private(set) var reminderScheduler: ReminderScheduler?

    override init() {
        let launchOptions = AppLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        let defaults = if launchOptions.usesInMemoryStore {
            UserDefaults(
                suiteName: "CornerPet.UITesting.\(UUID().uuidString)"
            )!
        } else {
            UserDefaults.standard
        }
        let appSettings = AppSettings(defaults: defaults)
        if let languageOverride = launchOptions.languageOverride {
            appSettings.setLanguage(languageOverride)
        }
        let launchAtLoginController = LaunchAtLoginController()
        let screenCoordinator = ScreenCoordinator()
        self.launchOptions = launchOptions
        self.appSettings = appSettings
        self.launchAtLoginController = launchAtLoginController
        self.screenCoordinator = screenCoordinator
        reminderStateStore = ReminderStateStore(defaults: defaults)
        panelControllerFactory = {
            CapturePanelController(
                screenProvider: { screenID in
                    Self.screen(withID: screenID)
                },
                corner: appSettings.triggerCorner,
                loadPinnedSize: { appSettings.lastPinnedSize },
                savePinnedSize: { appSettings.setLastPinnedSize($0) }
            )
        }
        triggerCoordinatorFactory = { panelController in
            CornerTriggerCoordinator(
                screenSnapshotsProvider: {
                    screenCoordinator.currentConfiguration?.enabledScreens ?? []
                },
                corner: appSettings.triggerCorner,
                presentPanel: { [weak panelController] screenID in
                    panelController?.present(screenID: screenID)
                },
                reverseClosingPanel: { [weak panelController] _ in
                    panelController?.reverseClosing()
                },
                isPanelPinned: { [weak panelController] in
                    panelController?.isPinned ?? false
                },
                bringPinnedPanelForward: { [weak panelController] in
                    panelController?.bringForward()
                }
            )
        }
        lifecycleCoordinatorFactory = { panelController in
            PanelLifecycleCoordinator(
                panelController: panelController,
                pointerInsideKeepOpen: { [weak panelController] in
                    if launchOptions.keepsCaptureOpen { return true }
                    guard let frame = panelController?.keepOpenFrame else { return false }
                    return frame.contains(NSEvent.mouseLocation)
                }
            )
        }
        compositionFactory = { panelController in
            let container = if launchOptions.usesInMemoryStore {
                try ModelContainerFactory.makeInMemory()
            } else {
                try ModelContainerFactory.makeProduction()
            }
            return CaptureCompositionRoot(
                container: container,
                panelController: panelController,
                failPermanentDeletes: launchOptions.usesDeleteFailureFixture
            )
        }
        super.init()
    }

    init(
        panelControllerFactory: @escaping PanelControllerFactory,
        triggerCoordinatorFactory: @escaping TriggerCoordinatorFactory,
        appSettings: AppSettings? = nil,
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        screenCoordinator: ScreenCoordinator = ScreenCoordinator(),
        compositionFactory: @escaping CompositionFactory = { _ in nil },
        launchOptions: AppLaunchOptions = AppLaunchOptions(arguments: []),
        reminderStateStore: (any ReminderStateStoring)? = nil,
        lifecycleCoordinatorFactory: @escaping LifecycleCoordinatorFactory = { panelController in
            PanelLifecycleCoordinator(panelController: panelController)
        }
    ) {
        let appSettings = appSettings ?? AppSettings(defaults: UserDefaults(
            suiteName: "CornerPet.AppDelegate.Isolated.\(UUID().uuidString)"
        ) ?? .standard)
        if let languageOverride = launchOptions.languageOverride {
            appSettings.setLanguage(languageOverride)
        }
        self.panelControllerFactory = panelControllerFactory
        self.triggerCoordinatorFactory = triggerCoordinatorFactory
        self.appSettings = appSettings
        self.launchAtLoginController = launchAtLoginController
        self.screenCoordinator = screenCoordinator
        self.lifecycleCoordinatorFactory = lifecycleCoordinatorFactory
        self.compositionFactory = compositionFactory
        self.launchOptions = launchOptions
        self.reminderStateStore = reminderStateStore ?? ReminderStateStore(defaults: UserDefaults(
            suiteName: "CornerPet.AppDelegate.Reminder.\(UUID().uuidString)"
        )!)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppConfiguration.activationPolicy)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard panelController == nil, triggerCoordinator == nil else {
            return
        }

        let panelController = panelControllerFactory()
        let composition: (any CaptureComposing)?
        do {
            composition = try compositionFactory(panelController)
            if let composition {
                panelController.installHostedContentFactory { [appSettings] in
                    NSHostingView(rootView: AppLocaleScope(settings: appSettings) {
                        composition.makeRootView()
                    })
                }
            }
        } catch {
            composition = nil
            NSLog("CornerPet persistence initialization failed: %@", String(describing: error))
            panelController.installHostedContentFactory { [appSettings] in
                NSHostingView(rootView: AppLocaleScope(settings: appSettings) {
                    CapturePersistenceErrorView()
                })
            }
        }
        let lifecycleCoordinator = lifecycleCoordinatorFactory(panelController)
        let triggerCoordinator = triggerCoordinatorFactory(panelController)
        let petReminderPanelController = PetReminderPanelController(
            settings: appSettings,
            onOpenInbox: { [weak self] in
                self?.openInboxFromReminder()
            },
            onSnooze: { [weak self] in
                self?.snoozeReminder()
            },
            onDismissToday: { [weak self] in
                self?.dismissReminderForToday()
            }
        )
        let reminderScheduler = ReminderScheduler(
            stateStore: reminderStateStore,
            isCaptureVisible: { [weak panelController] in
                panelController?.isVisible ?? false
            },
            isReminderVisible: { [weak petReminderPanelController] in
                petReminderPanelController?.isVisible ?? false
            },
            onPresent: { [weak self, weak petReminderPanelController] _ in
                guard let self,
                      let configuration = self.screenCoordinator.currentConfiguration else {
                    return
                }
                petReminderPanelController?.present(
                    corner: self.appSettings.triggerCorner,
                    screens: configuration.allScreens,
                    primaryDisplayID: configuration.primaryDisplayID
                )
            }
        )

        triggerCoordinator.onPresentRequested = {
            [weak petReminderPanelController, weak lifecycleCoordinator] screenID in
            petReminderPanelController?.dismiss()
            lifecycleCoordinator?.presentRequested(screenID: screenID)
        }
        triggerCoordinator.onReverseClosingRequested = { [weak lifecycleCoordinator] _ in
            lifecycleCoordinator?.reverseClosing()
        }
        triggerCoordinator.onTriggerPresenceChanged = { [weak lifecycleCoordinator] isInside in
            lifecycleCoordinator?.setTriggerPresence(isInside)
        }

        self.panelController = panelController
        self.triggerCoordinator = triggerCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
        self.composition = composition
        self.petReminderPanelController = petReminderPanelController
        self.reminderScheduler = reminderScheduler

        screenCoordinator.onChange = {
            [weak self, weak panelController, weak triggerCoordinator, weak petReminderPanelController]
            configuration in
            triggerCoordinator?.updateScreens(configuration.enabledScreens)
            panelController?.handleScreenConfigurationChange(configuration)
            if petReminderPanelController?.isVisible == true, let self {
                petReminderPanelController?.updatePlacement(
                    corner: self.appSettings.triggerCorner,
                    screens: configuration.allScreens,
                    primaryDisplayID: configuration.primaryDisplayID
                )
            }
        }
        appSettings.onChange = {
            [weak self, weak panelController, weak triggerCoordinator, weak petReminderPanelController]
            change in
            switch change.field {
            case .triggerCorner:
                panelController?.updateCorner(change.snapshot.triggerCorner)
                triggerCoordinator?.updateCorner(change.snapshot.triggerCorner)
                if petReminderPanelController?.isVisible == true,
                   let configuration = self?.screenCoordinator.currentConfiguration {
                    petReminderPanelController?.updatePlacement(
                        corner: change.snapshot.triggerCorner,
                        screens: configuration.allScreens,
                        primaryDisplayID: configuration.primaryDisplayID
                    )
                }
            case .displayScope:
                self?.screenCoordinator.updateScope(change.snapshot.displayScope)
            case .dailyReminderMinutes:
                self?.updateReminderConfiguration(change.snapshot)
            case .reminderEnabled:
                if !change.snapshot.reminderEnabled {
                    petReminderPanelController?.dismiss()
                }
                self?.updateReminderConfiguration(change.snapshot)
            case .lastPinnedSize, .language:
                break
            }
        }

        let togglePin: @MainActor @Sendable () -> Void = { [weak panelController, weak lifecycleCoordinator] in
            let pointerInside = panelController?.keepOpenFrame?.contains(NSEvent.mouseLocation) ?? false
            lifecycleCoordinator?.pinToggled(pointerInsideKeepOpen: pointerInside)
        }
        composition?.configurePanelPinning(
            isPinned: { [weak lifecycleCoordinator] in
                lifecycleCoordinator?.isPinned ?? false
            },
            onTogglePin: togglePin
        )

        composition?.onAutoHideProtectionChanged = { [weak self, weak lifecycleCoordinator] _ in
            let content = self?.composition?.panelContentStatus
                ?? PanelContentStatus(hasDraft: false, hasItemEdit: false, hasError: false)
            lifecycleCoordinator?.contentChanged(content, pointerInsideKeepOpen: false)
        }

        panelController.onLifecycle = { [weak self, weak triggerCoordinator, weak lifecycleCoordinator] event in
            switch event {
            case let .beganOpening(screenID):
                triggerCoordinator?.panelBeganOpening()
                lifecycleCoordinator?.presentRequested(screenID: screenID)
                lifecycleCoordinator?.didBeginOpening(screenID: screenID)
            case .didOpen:
                triggerCoordinator?.panelDidOpen()
                self?.composition?.captureViewModel.panelDidOpen()
                lifecycleCoordinator?.didOpen(
                    content: self?.composition?.panelContentStatus
                        ?? PanelContentStatus(hasDraft: false, hasItemEdit: false, hasError: false),
                    pointerInsideKeepOpen: false
                )
            case .beganClosing:
                triggerCoordinator?.panelBeganClosing()
                lifecycleCoordinator?.didBeginClosing()
            case .didClose:
                triggerCoordinator?.panelDidClose()
                lifecycleCoordinator?.didClose()
            }
        }
        panelController.onPointerBoundaryChanged = { [weak lifecycleCoordinator] in
            lifecycleCoordinator?.refreshPresence()
        }
        panelController.onEscape = { [weak lifecycleCoordinator] in
            lifecycleCoordinator?.closeRequested()
        }
        panelController.onExternalFocusLost = { [weak self, weak lifecycleCoordinator] in
            self?.composition?.captureViewModel.flushDraft()
            let saveResult = self?.composition?.saveActiveEditForExternalFocus()
            let succeeded: Bool? = saveResult.map { result in
                if case .saved = result { return true }
                return false
            }
            let content = self?.composition?.panelContentStatus
                ?? PanelContentStatus(hasDraft: false, hasItemEdit: false, hasError: false)
            lifecycleCoordinator?.contentChanged(content, pointerInsideKeepOpen: false)
            lifecycleCoordinator?.externalFocusLost(editSaveSucceeded: succeeded)
        }
        panelController.onReturnToCorner = { [weak panelController, weak lifecycleCoordinator] in
            let pointerInside = panelController?.keepOpenFrame?.contains(NSEvent.mouseLocation) ?? false
            lifecycleCoordinator?.didReturnToCorner(pointerInsideKeepOpen: pointerInside)
        }
        panelController.onCornerChanged = { [weak self] corner in
            self?.appSettings.setTriggerCorner(corner)
        }

        if launchOptions.showsReminder, let reminderCorner = launchOptions.reminderCorner {
            appSettings.setTriggerCorner(reminderCorner)
        }
        screenCoordinator.start(scope: appSettings.displayScope)
        reminderScheduler.start(configuration: ReminderConfiguration(
            isEnabled: appSettings.reminderEnabled,
            dailyMinutes: appSettings.dailyReminderMinutes
        ))
        _ = triggerCoordinator.start()
        if launchOptions.handlesCommandCommaSignal {
            Darwin.signal(SIGUSR1, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            signalSource.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.dispatchCommandComma()
                }
            }
            signalSource.resume()
            commandCommaSignalSource = signalSource
        }
        if launchOptions.opensCapture,
           let screenID = screenCoordinator.currentConfiguration?.primaryDisplayID {
            petReminderPanelController.dismiss()
            if !launchOptions.opensCaptureWithoutActivation {
                NSApp.activate()
            }
            lifecycleCoordinator.presentRequested(screenID: screenID)
            panelController.present(screenID: screenID)
        } else if launchOptions.showsReminder,
                  let configuration = screenCoordinator.currentConfiguration {
            petReminderPanelController.present(
                corner: appSettings.triggerCorner,
                screens: configuration.allScreens,
                primaryDisplayID: configuration.primaryDisplayID
            )
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLoginController.refresh()
    }

    func focusLibrarySearch() {
        _ = panelController?.requestSearchFocus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandCommaSignalSource?.cancel()
        commandCommaSignalSource = nil
        reminderScheduler?.stop()
        petReminderPanelController?.dismiss()
        composition?.applicationWillTerminate()
        lifecycleCoordinator?.stop()
        triggerCoordinator?.stop()
        screenCoordinator.stop()
    }

    private func updateReminderConfiguration(_ snapshot: AppSettingsSnapshot) {
        reminderScheduler?.update(configuration: ReminderConfiguration(
            isEnabled: snapshot.reminderEnabled,
            dailyMinutes: snapshot.dailyReminderMinutes
        ))
    }

    private func openInboxFromReminder() {
        let screenID = petReminderPanelController?.currentScreenID
            ?? screenCoordinator.currentConfiguration?.primaryDisplayID
        reminderScheduler?.completeCurrentReminder()
        petReminderPanelController?.dismiss()
        composition?.selectInbox()
        NSApp.activate()

        guard let screenID else { return }
        lifecycleCoordinator?.presentRequested(screenID: screenID)
        if panelController?.isVisible == true {
            panelController?.panel?.orderFrontRegardless()
            panelController?.panel?.makeKey()
        }
    }

    private func snoozeReminder() {
        reminderScheduler?.snooze()
        petReminderPanelController?.dismiss()
    }

    private func dismissReminderForToday() {
        reminderScheduler?.completeCurrentReminder()
        petReminderPanelController?.dismiss()
    }

    private static func screen(withID screenID: UInt32) -> NSScreen? {
        NSScreen.screens.first { screen in
            displayID(for: screen) == screenID
        }
    }

    private func dispatchCommandComma() {
        guard launchOptions.handlesCommandCommaSignal,
              launchOptions.opensCaptureWithoutActivation,
              let panel = panelController?.panel,
              let event = NSEvent.keyEvent(
                  with: .keyDown,
                  location: .zero,
                  modifierFlags: [.command],
                  timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: panel.windowNumber,
                  context: nil,
                  characters: ",",
                  charactersIgnoringModifiers: ",",
                  isARepeat: false,
                  keyCode: 43
              ) else {
            return
        }
        panel.sendEvent(event)
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private struct CapturePersistenceErrorView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.orange)
            Text("无法打开本地存储")
                .font(.headline)
            Text("Local storage is unavailable")
                .foregroundStyle(.secondary)
            Text("请重新启动 CornerPet 后再试 / Restart CornerPet and try again")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(
            width: CaptureLayout.panelSize.width,
            height: CaptureLayout.panelSize.height
        )
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.persistence.error")
    }
}

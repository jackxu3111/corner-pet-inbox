import AppKit
import SwiftUI

struct AppLaunchOptions: Equatable {
    let usesInMemoryStore: Bool
    let opensCapture: Bool
    let usesDeleteFailureFixture: Bool

    init(arguments: [String]) {
        let isUITesting = arguments.contains("--cornerpet-ui-testing")
        usesInMemoryStore = isUITesting
            && arguments.contains("--cornerpet-memory-store")
        opensCapture = isUITesting
            && arguments.contains("--cornerpet-open-capture")
        usesDeleteFailureFixture = usesInMemoryStore
            && arguments.contains("--cornerpet-ui-delete-failure")
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
    private let triggerCornerStore: TriggerCornerStore
    private let lifecycleCoordinatorFactory: LifecycleCoordinatorFactory
    private let compositionFactory: CompositionFactory
    private let launchOptions: AppLaunchOptions

    private(set) var panelController: CapturePanelController?
    private(set) var triggerCoordinator: CornerTriggerCoordinator?
    private(set) var lifecycleCoordinator: PanelLifecycleCoordinator?
    private(set) var composition: (any CaptureComposing)?

    override init() {
        let launchOptions = AppLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        let triggerCornerStore = TriggerCornerStore()
        self.launchOptions = launchOptions
        self.triggerCornerStore = triggerCornerStore
        panelControllerFactory = {
            CapturePanelController(
                screenProvider: { screenID in
                    Self.screen(withID: screenID)
                },
                corner: triggerCornerStore.load()
            )
        }
        triggerCoordinatorFactory = { panelController in
            CornerTriggerCoordinator(
                screenProvider: { NSScreen.main },
                corner: triggerCornerStore.load(),
                presentPanel: { [weak panelController] screenID in
                    panelController?.present(screenID: screenID)
                },
                reverseClosingPanel: { [weak panelController] _ in
                    panelController?.reverseClosing()
                }
            )
        }
        lifecycleCoordinatorFactory = { panelController in
            PanelLifecycleCoordinator(
                panelController: panelController,
                pointerInsideKeepOpen: { [weak panelController] in
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
        triggerCornerStore: TriggerCornerStore = TriggerCornerStore(),
        compositionFactory: @escaping CompositionFactory = { _ in nil },
        launchOptions: AppLaunchOptions = AppLaunchOptions(arguments: []),
        lifecycleCoordinatorFactory: @escaping LifecycleCoordinatorFactory = { panelController in
            PanelLifecycleCoordinator(panelController: panelController)
        }
    ) {
        self.panelControllerFactory = panelControllerFactory
        self.triggerCoordinatorFactory = triggerCoordinatorFactory
        self.triggerCornerStore = triggerCornerStore
        self.lifecycleCoordinatorFactory = lifecycleCoordinatorFactory
        self.compositionFactory = compositionFactory
        self.launchOptions = launchOptions
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
                panelController.installHostedContentFactory {
                    NSHostingView(rootView: composition.makeRootView())
                }
            }
        } catch {
            composition = nil
            NSLog("CornerPet persistence initialization failed: %@", String(describing: error))
            panelController.installHostedContentFactory {
                NSHostingView(rootView: CapturePersistenceErrorView())
            }
        }
        let lifecycleCoordinator = lifecycleCoordinatorFactory(panelController)
        let triggerCoordinator = triggerCoordinatorFactory(panelController)

        triggerCoordinator.onPresentRequested = { [weak lifecycleCoordinator] screenID in
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
        panelController.onCornerChanged = { [weak self, weak triggerCoordinator] corner in
            self?.triggerCornerStore.save(corner)
            triggerCoordinator?.updateCorner(corner)
        }

        _ = triggerCoordinator.start()
        if launchOptions.opensCapture,
           let screen = NSScreen.main,
           let screenID = Self.displayID(for: screen) {
            lifecycleCoordinator.presentRequested(screenID: screenID)
            panelController.present(screenID: screenID)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition?.applicationWillTerminate()
        lifecycleCoordinator?.stop()
        triggerCoordinator?.stop()
    }

    private static func screen(withID screenID: UInt32) -> NSScreen? {
        NSScreen.screens.first { screen in
            displayID(for: screen) == screenID
        }
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

import AppKit
import XCTest

@testable import CornerPet

final class AppConfigurationTests: XCTestCase {
    func testMinimumMacOSMajorVersionIs14() {
        XCTAssertEqual(AppConfiguration.minimumMacOSMajorVersion, 14)
    }

    func testProductNamesAreStable() {
        XCTAssertEqual(AppConfiguration.englishProductName, "CornerPet")
        XCTAssertEqual(AppConfiguration.chineseProductName, "角落灵感箱")
        XCTAssertEqual(AppConfiguration.displayName, "CornerPet / 角落灵感箱")
    }

    func testActivationPolicyIsAccessory() {
        XCTAssertEqual(AppConfiguration.activationPolicy, .accessory)
    }

    func testUITestLaunchOptionsRequireTheMasterGate() {
        let ungated = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture",
            "--cornerpet-ui-open-capture-without-activation",
            "--cornerpet-ui-delete-failure",
            "--cornerpet-ui-keep-capture-open",
            "--cornerpet-ui-command-comma-signal",
            "--cornerpet-ui-show-reminder",
            "--cornerpet-ui-reminder-corner=bottomRight"
        ])
        let gated = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture"
        ])
        let failureFixture = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture",
            "--cornerpet-ui-delete-failure"
        ])
        let keepOpenFixture = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-keep-capture-open"
        ])
        let nonactivatingOpenFixture = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-open-capture-without-activation",
            "--cornerpet-ui-command-comma-signal"
        ])
        let reminderFixture = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-ui-show-reminder",
            "--cornerpet-ui-reminder-corner=bottomRight"
        ])
        let reminderWithoutMemoryStore = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-show-reminder",
            "--cornerpet-ui-reminder-corner=bottomRight"
        ])

        XCTAssertFalse(ungated.usesInMemoryStore)
        XCTAssertFalse(ungated.opensCapture)
        XCTAssertFalse(ungated.usesDeleteFailureFixture)
        XCTAssertFalse(ungated.keepsCaptureOpen)
        XCTAssertFalse(ungated.opensCaptureWithoutActivation)
        XCTAssertFalse(ungated.handlesCommandCommaSignal)
        XCTAssertFalse(ungated.showsReminder)
        XCTAssertNil(ungated.reminderCorner)
        XCTAssertTrue(gated.usesInMemoryStore)
        XCTAssertTrue(gated.opensCapture)
        XCTAssertFalse(gated.opensCaptureWithoutActivation)
        XCTAssertFalse(gated.usesDeleteFailureFixture)
        XCTAssertTrue(failureFixture.usesDeleteFailureFixture)
        XCTAssertTrue(keepOpenFixture.keepsCaptureOpen)
        XCTAssertTrue(nonactivatingOpenFixture.opensCapture)
        XCTAssertTrue(nonactivatingOpenFixture.opensCaptureWithoutActivation)
        XCTAssertTrue(nonactivatingOpenFixture.handlesCommandCommaSignal)
        XCTAssertTrue(reminderFixture.showsReminder)
        XCTAssertEqual(reminderFixture.reminderCorner, .bottomRight)
        XCTAssertFalse(reminderWithoutMemoryStore.showsReminder)
        XCTAssertNil(reminderWithoutMemoryStore.reminderCorner)
    }

    func testUITestLanguageOverrideRequiresMasterGateAndKnownLanguage() {
        let ungated = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-language=zh-Hans"
        ])
        let english = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=en"
        ])
        let simplifiedChinese = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=zh-Hans"
        ])
        let system = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=system"
        ])
        let unknown = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=fr"
        ])

        XCTAssertNil(ungated.languageOverride)
        XCTAssertEqual(english.languageOverride, .english)
        XCTAssertEqual(simplifiedChinese.languageOverride, .simplifiedChinese)
        XCTAssertEqual(system.languageOverride, .system)
        XCTAssertNil(unknown.languageOverride)
    }
}

@MainActor
final class AppDelegateIntegrationTests: XCTestCase {
    func testUITestLanguageOverrideIsAppliedTransientlyBeforeRuntimeComposition() {
        let defaults = UserDefaults(
            suiteName: "CornerPet.AppDelegateLanguage.\(UUID().uuidString)"
        )!
        defaults.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppSettingsStorageKey.language
        )
        let settings = AppSettings(defaults: defaults)
        let launchOptions = AppLaunchOptions(arguments: [
            "CornerPet",
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=en"
        ])

        _ = AppDelegate(
            panelControllerFactory: { self.makePanelController() },
            triggerCoordinatorFactory: { _ in
                CornerTriggerCoordinator(
                    screenSnapshotsProvider: { [] },
                    presentPanel: { _ in },
                    reverseClosingPanel: { _ in }
                )
            },
            appSettings: settings,
            launchOptions: launchOptions
        )

        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(
            defaults.string(forKey: AppSettingsStorageKey.language),
            AppLanguage.simplifiedChinese.rawValue
        )
    }

    func testDisplayScopeChangesImmediatelyReconfigureRuntimeTriggerScreens() {
        let first = ScreenSnapshot(
            id: 101,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let second = ScreenSnapshot(
            id: 202,
            frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_055)
        )
        let settings = AppSettings(defaults: UserDefaults(
            suiteName: "CornerPet.AppDelegateDisplayScope.\(UUID().uuidString)"
        )!)
        let screenCoordinator = ScreenCoordinator(
            screensProvider: { [first, second] },
            primaryDisplayIDProvider: { first.id }
        )
        let panel = makePanelController()
        let trigger = CornerTriggerCoordinator(
            screenSnapshotsProvider: { [] },
            pointerLocationProvider: { CGPoint(x: 500, y: 500) },
            presentPanel: { _ in },
            reverseClosingPanel: { _ in }
        )
        let appDelegate = AppDelegate(
            panelControllerFactory: { panel },
            triggerCoordinatorFactory: { _ in trigger },
            appSettings: settings,
            screenCoordinator: screenCoordinator
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        XCTAssertEqual(trigger.triggerScreenIDs, [101])

        settings.setDisplayScope(.all)

        XCTAssertEqual(trigger.triggerScreenIDs, [101, 202])
    }

    func testNormalAndLoginLaunchPathStayHiddenUntilExplicitlyTriggered() throws {
        let panel = makePanelController()
        let coordinator = try makeCoordinator()
        let appDelegate = AppDelegate(
            panelControllerFactory: { panel },
            triggerCoordinatorFactory: { _ in coordinator }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(coordinator.isRunning)
    }

    func testLaunchAlwaysCreatesMainScreenTopLeftTriggerWithoutPermissionGate() throws {
        var panelFactoryCalls = 0
        var coordinatorFactoryCalls = 0
        let panel = makePanelController()
        let coordinator = try makeCoordinator()
        let appDelegate = AppDelegate(
            panelControllerFactory: {
                panelFactoryCalls += 1
                return panel
            },
            triggerCoordinatorFactory: { _ in
                coordinatorFactoryCalls += 1
                return coordinator
            }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        XCTAssertEqual(panelFactoryCalls, 1)
        XCTAssertEqual(coordinatorFactoryCalls, 1)
        XCTAssertNotNil(appDelegate.panelController)
        XCTAssertNotNil(appDelegate.triggerCoordinator)
    }

    func testTerminationStopsTriggerCoordinator() throws {
        let coordinator = try makeCoordinator()
        let appDelegate = AppDelegate(
            panelControllerFactory: { self.makePanelController() },
            triggerCoordinatorFactory: { _ in coordinator }
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        appDelegate.applicationWillTerminate(Notification(name: .init("test")))

        XCTAssertFalse(coordinator.isRunning)
    }

    func testReminderRuntimeStartsAtLaunchAndStopsAtTermination() throws {
        let coordinator = try makeCoordinator()
        let defaults = UserDefaults(
            suiteName: "CornerPet.AppDelegateReminderRuntime.\(UUID().uuidString)"
        )!
        let settings = AppSettings(defaults: defaults)
        settings.setReminderEnabled(false)
        let appDelegate = AppDelegate(
            panelControllerFactory: { self.makePanelController() },
            triggerCoordinatorFactory: { _ in coordinator },
            appSettings: settings
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        XCTAssertNotNil(appDelegate.petReminderPanelController)
        XCTAssertEqual(appDelegate.reminderScheduler?.isRunning, true)

        appDelegate.applicationWillTerminate(Notification(name: .init("test")))

        XCTAssertEqual(appDelegate.reminderScheduler?.isRunning, false)
        XCTAssertEqual(appDelegate.petReminderPanelController?.isVisible, false)
    }

    func testCapturePresentationDismissesVisiblePetReminder() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let screenID = try XCTUnwrap(Self.displayID(for: screen))
        let snapshot = ScreenSnapshot(
            id: screenID,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        let defaults = UserDefaults(
            suiteName: "CornerPet.AppDelegateReminderConflict.\(UUID().uuidString)"
        )!
        let settings = AppSettings(defaults: defaults)
        settings.setReminderEnabled(false)
        let screenCoordinator = ScreenCoordinator(
            screensProvider: { [snapshot] },
            primaryDisplayIDProvider: { screenID }
        )
        let panel = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            }
        )
        let coordinator = try makeCoordinator()
        let appDelegate = AppDelegate(
            panelControllerFactory: { panel },
            triggerCoordinatorFactory: { _ in coordinator },
            appSettings: settings,
            screenCoordinator: screenCoordinator
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        let pet = try XCTUnwrap(appDelegate.petReminderPanelController)
        pet.present(corner: .topLeft, screens: [snapshot], primaryDisplayID: screenID)
        XCTAssertTrue(pet.isVisible)

        coordinator.onPresentRequested?(screenID)

        XCTAssertFalse(pet.isVisible)
        XCTAssertTrue(panel.isVisible)
    }

    func testDisablingReminderImmediatelyDismissesVisiblePet() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let screenID = try XCTUnwrap(Self.displayID(for: screen))
        let snapshot = ScreenSnapshot(
            id: screenID,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        let defaults = UserDefaults(
            suiteName: "CornerPet.AppDelegateReminderDisable.\(UUID().uuidString)"
        )!
        let settings = AppSettings(defaults: defaults)
        let screenCoordinator = ScreenCoordinator(
            screensProvider: { [snapshot] },
            primaryDisplayIDProvider: { screenID }
        )
        let coordinator = try makeCoordinator()
        let appDelegate = AppDelegate(
            panelControllerFactory: { self.makePanelController() },
            triggerCoordinatorFactory: { _ in coordinator },
            appSettings: settings,
            screenCoordinator: screenCoordinator
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        let pet = try XCTUnwrap(appDelegate.petReminderPanelController)
        pet.present(corner: .bottomRight, screens: [snapshot], primaryDisplayID: screenID)
        XCTAssertTrue(pet.isVisible)

        settings.setReminderEnabled(false)

        XCTAssertFalse(pet.isVisible)
        XCTAssertEqual(appDelegate.reminderScheduler?.lastEvaluationReason, .settingsChanged)
    }

    func testPanelLifecycleAndBoundaryCallbacksReachCoordinator() throws {
        let coordinator = try makeCoordinator()
        let panel = makePanelController()
        let appDelegate = AppDelegate(
            panelControllerFactory: { panel },
            triggerCoordinatorFactory: { _ in coordinator }
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        XCTAssertNotNil(panel.onLifecycle)
        XCTAssertNotNil(panel.onPointerBoundaryChanged)
        XCTAssertNotNil(panel.onEscape)
    }

    func testCornerChangePersistsAndImmediatelyReconfiguresTheTrigger() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let defaults = UserDefaults(
            suiteName: "CornerPet.AppDelegateCornerTests.\(UUID().uuidString)"
        )!
        let settings = AppSettings(defaults: defaults)
        let panel = makePanelController()
        let coordinator = CornerTriggerCoordinator(
            screenProvider: { screen },
            corner: .topLeft,
            clock: { 0 },
            pointerLocationProvider: { CGPoint(x: screen.frame.midX, y: screen.frame.midY) },
            scheduler: ManualDeadlineScheduler(),
            presentPanel: { _ in },
            reverseClosingPanel: { _ in }
        )
        let appDelegate = AppDelegate(
            panelControllerFactory: { panel },
            triggerCoordinatorFactory: { _ in coordinator },
            appSettings: settings
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        panel.onCornerChanged?(.bottomRight)

        XCTAssertEqual(TriggerCornerStore(defaults: defaults).load(), .bottomRight)
        XCTAssertEqual(coordinator.corner, .bottomRight)
        let expected = TriggerZonePanel.frames(for: screen.frame, corner: .bottomRight)
        XCTAssertEqual(coordinator.horizontalPanel?.frame, expected.horizontal)
        XCTAssertEqual(coordinator.verticalPanel?.frame, expected.vertical)
    }

    func testCrossScreenReturnCanReverseFromNewMainScreenHotCornerAndTriggerAgain() throws {
        let mainScreen = try XCTUnwrap(NSScreen.screens.first)
        let mainScreenID = try XCTUnwrap(Self.displayID(for: mainScreen))
        let secondaryScreenID = mainScreenID == UInt32.max ? mainScreenID - 1 : mainScreenID + 1
        let secondaryFrame = CGRect(
            x: mainScreen.frame.maxX,
            y: mainScreen.frame.minY,
            width: 1_000,
            height: 800
        )
        let defaults = UserDefaults(
            suiteName: "CornerPet.CrossScreenReentryTests.\(UUID().uuidString)"
        )!
        var now: TimeInterval = 0
        var pointer = Self.point(in: mainScreen.frame, corner: .topLeft)
        let scheduler = ManualDeadlineScheduler()
        let panel = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == mainScreenID ? mainScreen : nil
            },
            screensProvider: {
                [
                    PanelScreenGeometry(
                        id: mainScreenID,
                        frame: mainScreen.frame,
                        visibleFrame: mainScreen.visibleFrame
                    ),
                    PanelScreenGeometry(
                        id: secondaryScreenID,
                        frame: secondaryFrame,
                        visibleFrame: secondaryFrame
                    )
                ]
            },
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: PinnedPanelSizeStore(defaults: defaults)
        )
        let coordinator = CornerTriggerCoordinator(
            screenProvider: { mainScreen },
            clock: { now },
            pointerLocationProvider: { pointer },
            scheduler: scheduler,
            presentPanel: { _ in },
            reverseClosingPanel: { _ in }
        )
        let appDelegate = AppDelegate(
            panelControllerFactory: { panel },
            triggerCoordinatorFactory: { _ in coordinator },
            appSettings: AppSettings(defaults: defaults)
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        now = 0.400
        scheduler.fire(0)
        now = 0.520
        _ = panel.tick(at: now)
        appDelegate.lifecycleCoordinator?.pinToggled(pointerInsideKeepOpen: true)
        panel.panel?.setFrame(
            CGRect(
                x: secondaryFrame.maxX - 350,
                y: secondaryFrame.minY + 50,
                width: 300,
                height: 350
            ),
            display: false
        )
        pointer = CGPoint(x: mainScreen.frame.midX, y: mainScreen.frame.midY)
        coordinator.refreshPresence()
        appDelegate.lifecycleCoordinator?.pinToggled(pointerInsideKeepOpen: false)
        now = 0.640
        _ = panel.tick(at: now)

        XCTAssertEqual(panel.animationDirection, .closing)
        XCTAssertEqual(coordinator.corner, .bottomRight)

        pointer = Self.point(in: mainScreen.frame, corner: .bottomRight)
        now = 0.650
        coordinator.refreshPresence()

        XCTAssertEqual(panel.animationDirection, .opening)

        now = 0.770
        _ = panel.tick(at: now)
        pointer = CGPoint(x: mainScreen.frame.midX, y: mainScreen.frame.midY)
        now = 0.780
        coordinator.refreshPresence()
        appDelegate.lifecycleCoordinator?.closeRequested()
        now = 1
        _ = panel.tick(at: now)
        XCTAssertFalse(panel.isVisible)

        pointer = Self.point(in: mainScreen.frame, corner: .bottomRight)
        now = 1.010
        coordinator.refreshPresence()
        XCTAssertEqual(scheduler.tokens.count, 2)
        let nextDwell = try XCTUnwrap(scheduler.tokens.indices.last)
        now = 2
        scheduler.fire(nextDwell)

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.animationDirection, .opening)
    }

    private func makePanelController() -> CapturePanelController {
        CapturePanelController(
            screenProvider: { _ in nil }
        )
    }

    private func makeCoordinator() throws -> CornerTriggerCoordinator {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for coordinator integration tests")
        }
        let scheduler = ManualDeadlineScheduler()
        return CornerTriggerCoordinator(
            screenProvider: { screen },
            clock: { 0 },
            pointerLocationProvider: { CGPoint(x: screen.frame.midX, y: screen.frame.midY) },
            scheduler: scheduler,
            presentPanel: { _ in },
            reverseClosingPanel: { _ in }
        )
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func point(in frame: CGRect, corner: TriggerCorner) -> CGPoint {
        switch corner {
        case .topLeft:
            CGPoint(x: frame.minX + 10, y: frame.maxY - 10)
        case .topRight:
            CGPoint(x: frame.maxX - 10, y: frame.maxY - 10)
        case .bottomLeft:
            CGPoint(x: frame.minX + 10, y: frame.minY + 10)
        case .bottomRight:
            CGPoint(x: frame.maxX - 10, y: frame.minY + 10)
        }
    }
}

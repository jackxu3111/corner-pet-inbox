import XCTest

@testable import CornerPet

@MainActor
final class PanelLifecycleCoordinatorTests: XCTestCase {
    private let empty = PanelContentStatus(
        hasDraft: false,
        hasItemEdit: false,
        hasError: false
    )
    private let draft = PanelContentStatus(
        hasDraft: true,
        hasItemEdit: false,
        hasError: false
    )

    func testOnlyLifecycleCoordinatorSchedulesPanelExitDeadline() throws {
        var now = 10.0
        var inside = true
        let scheduler = ManualDeadlineScheduler()
        var dismissCount = 0
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { inside },
            dismiss: { dismissCount += 1 }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        inside = false
        now = 20
        coordinator.refreshPresence()

        XCTAssertEqual(scheduler.scheduledDelays.count, 1)
        XCTAssertEqual(scheduler.scheduledDelays[0], 0.120, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(coordinator.nextDeadline).dueAt, 20.120, accuracy: 0.0000001)
        XCTAssertEqual(dismissCount, 0)
    }

    func testUnionReentryCancelsBeforeDeadline() {
        var now = 10.0
        var inside = true
        let scheduler = ManualDeadlineScheduler()
        var dismissCount = 0
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { inside },
            dismiss: { dismissCount += 1 }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        inside = false
        now = 20
        coordinator.refreshPresence()
        inside = true
        now = 20.050
        coordinator.refreshPresence()

        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        now = 20.120
        scheduler.fire(0)
        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(coordinator.state, .openEmpty)
    }

    func testDeadlineRechecksPointer() {
        var now = 10.0
        var inside = true
        let scheduler = ManualDeadlineScheduler()
        var dismissCount = 0
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { inside },
            dismiss: { dismissCount += 1 }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        inside = false
        now = 20
        coordinator.refreshPresence()
        inside = true
        now = 20.120
        scheduler.fire(0)

        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(coordinator.state, .openEmpty)
    }

    func testGenerationRejectsStaleDeadlineAfterReplacement() {
        var now = 10.0
        var inside = true
        let scheduler = ManualDeadlineScheduler()
        var dismissCount = 0
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { inside },
            dismiss: { dismissCount += 1 }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        inside = false
        now = 20
        coordinator.refreshPresence()
        inside = true
        now = 20.050
        coordinator.refreshPresence()
        inside = false
        now = 20.060
        coordinator.refreshPresence()

        XCTAssertEqual(scheduler.tokens.count, 2)
        now = 20.120
        scheduler.fire(0)
        XCTAssertEqual(dismissCount, 0)
        XCTAssertFalse(scheduler.tokens[1].isCancelled)
    }

    func testContentChangeCancelsPendingEmptyClose() {
        var now = 10.0
        var inside = true
        let scheduler = ManualDeadlineScheduler()
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { inside }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        inside = false
        now = 20
        coordinator.refreshPresence()
        coordinator.contentChanged(draft, pointerInsideKeepOpen: false)

        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertNil(coordinator.nextDeadline)
        XCTAssertEqual(coordinator.state, .draftLocked)
    }

    func testTriggerAndPanelPresenceAreReconciledAsOneUnion() {
        var now = 10.0
        var panelInside = false
        let scheduler = ManualDeadlineScheduler()
        var dismissCount = 0
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { panelInside },
            dismiss: { dismissCount += 1 }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        coordinator.setTriggerPresence(false, at: 20)
        XCTAssertEqual(scheduler.scheduledDelays.count, 1)
        XCTAssertEqual(scheduler.scheduledDelays[0], 0.120, accuracy: 0.0000001)

        panelInside = true
        now = 20.050
        coordinator.refreshPresence()

        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        now = 20.120
        scheduler.fire(0)
        XCTAssertEqual(dismissCount, 0)
    }

    func testExternalFocusResultAndContentStatusFlowThroughReducer() {
        let now = 10.0
        let scheduler = ManualDeadlineScheduler()
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { true }
        )
        let editing = PanelContentStatus(
            hasDraft: false,
            hasItemEdit: true,
            hasError: false
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: editing, pointerInsideKeepOpen: true)
        coordinator.externalFocusLost(editSaveSucceeded: false)

        XCTAssertEqual(coordinator.state, .error)
        coordinator.contentChanged(editing, pointerInsideKeepOpen: true)
        XCTAssertEqual(coordinator.state, .itemEditing)
    }

    func testStopCancelsTheOnePendingPanelDeadline() {
        var now = 10.0
        var inside = true
        let scheduler = ManualDeadlineScheduler()
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { inside }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        inside = false
        now = 20
        coordinator.refreshPresence()
        coordinator.stop()

        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertNil(coordinator.nextDeadline)
    }

    func testReturnToCornerUsesTriggerAndPanelUnionBeforeClosing() {
        var now = 10.0
        var panelInside = false
        let scheduler = ManualDeadlineScheduler()
        var dismissCount = 0
        let coordinator = makeCoordinator(
            scheduler: scheduler,
            now: { now },
            pointerInside: { panelInside },
            dismiss: { dismissCount += 1 }
        )

        coordinator.presentRequested(screenID: 1)
        coordinator.didOpen(content: empty, pointerInsideKeepOpen: true)
        coordinator.pinToggled(pointerInsideKeepOpen: true)
        coordinator.pinToggled(pointerInsideKeepOpen: false)
        coordinator.setTriggerPresence(true, at: now)
        coordinator.didReturnToCorner(pointerInsideKeepOpen: false)

        XCTAssertEqual(coordinator.state, .openEmpty)
        XCTAssertEqual(dismissCount, 0)

        panelInside = true
        now = 11
        coordinator.didReturnToCorner(pointerInsideKeepOpen: false)
        XCTAssertEqual(coordinator.state, .openEmpty)
        XCTAssertEqual(dismissCount, 0)
    }

    func testPinnedControllerIgnoresPointerExitAndExternalFocus() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for pinned lifecycle tests")
        }
        let screenID = try XCTUnwrap(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
        var now: TimeInterval = 0
        let scheduler = ManualDeadlineScheduler()
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        let coordinator = PanelLifecycleCoordinator(
            panelController: controller,
            scheduler: scheduler,
            clock: { now },
            pointerInsideKeepOpen: { false }
        )
        var lifecycleEvents: [CapturePanelLifecycleEvent] = []
        controller.onLifecycle = { event in
            lifecycleEvents.append(event)
            switch event {
            case let .beganOpening(screenID):
                coordinator.presentRequested(screenID: screenID)
                coordinator.didBeginOpening(screenID: screenID)
            case .didOpen:
                coordinator.didOpen(content: self.empty, pointerInsideKeepOpen: false)
            case .beganClosing:
                coordinator.didBeginClosing()
            case .didClose:
                coordinator.didClose()
            }
        }
        controller.onPointerBoundaryChanged = {
            coordinator.refreshPresence()
        }
        controller.onExternalFocusLost = { _ in
            coordinator.externalFocusLost(editSaveSucceeded: nil)
        }

        coordinator.presentRequested(screenID: screenID)
        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        XCTAssertEqual(coordinator.state, .openEmpty)

        coordinator.pinToggled(pointerInsideKeepOpen: true)
        XCTAssertEqual(coordinator.state, .pinned)
        XCTAssertTrue(controller.isPinned)

        now = 1
        coordinator.pointerChanged(isInsideKeepOpen: false, at: now)
        controller.windowDidResignKey(Notification(
            name: NSWindow.didResignKeyNotification,
            object: controller.panel
        ))

        XCTAssertEqual(coordinator.state, .pinned)
        XCTAssertTrue(controller.isPinned)
        XCTAssertTrue(controller.isVisible)
        XCTAssertFalse(lifecycleEvents.contains { event in
            if case .beganClosing = event { return true }
            return false
        })
    }

    private func makeCoordinator(
        scheduler: ManualDeadlineScheduler,
        now: @escaping @MainActor () -> TimeInterval,
        pointerInside: @escaping @MainActor () -> Bool,
        dismiss: @escaping @MainActor () -> Void = {}
    ) -> PanelLifecycleCoordinator {
        PanelLifecycleCoordinator(
            scheduler: scheduler,
            clock: now,
            pointerInsideKeepOpen: pointerInside,
            presentPanel: { _ in },
            dismissPanel: dismiss,
            reverseClosingPanel: { _ in }
        )
    }
}

import AppKit
import XCTest

@testable import CornerPet

@MainActor
final class ManualDeadlineScheduler: HotCornerDeadlineScheduling {
    final class Token: HotCornerCancellation {
        private(set) var isCancelled = false
        let operation: @MainActor () -> Void

        init(operation: @escaping @MainActor () -> Void) {
            self.operation = operation
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var tokens: [Token] = []

    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> HotCornerCancellation {
        scheduledDelays.append(delay)
        let token = Token(operation: operation)
        tokens.append(token)
        return token
    }

    func fire(_ index: Int) {
        tokens[index].operation()
    }
}

@MainActor
final class CornerTriggerCoordinatorTests: XCTestCase {
    func testStartCreatesTriggerPanelsAtEveryConfiguredCorner() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)

        for corner in TriggerCorner.allCases {
            let coordinator = makeCoordinator(
                screen: screen,
                corner: corner,
                pointer: { CGPoint(x: screen.frame.midX, y: screen.frame.midY) }
            )
            XCTAssertTrue(coordinator.start())

            let expected = TriggerZonePanel.frames(for: screen.frame, corner: corner)
            XCTAssertEqual(coordinator.horizontalPanel?.frame, expected.horizontal)
            XCTAssertEqual(coordinator.verticalPanel?.frame, expected.vertical)

            coordinator.stop()
        }
    }

    func testUpdatingCornerCancelsOldDwellAndOnlyNewCornerCanPresent() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = point(in: screen.frame, corner: .topLeft)
        let scheduler = ManualDeadlineScheduler()
        var presented = 0
        let coordinator = makeCoordinator(
            screen: screen,
            corner: .topLeft,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler,
            present: { _ in presented += 1 }
        )
        XCTAssertTrue(coordinator.start())
        XCTAssertEqual(scheduler.tokens.count, 1)

        coordinator.updateCorner(.bottomRight)

        let bottomRightFrames = TriggerZonePanel.frames(
            for: screen.frame,
            corner: .bottomRight
        )
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertEqual(coordinator.horizontalPanel?.frame, bottomRightFrames.horizontal)
        XCTAssertEqual(coordinator.verticalPanel?.frame, bottomRightFrames.vertical)

        now = 20.400
        scheduler.fire(0)
        XCTAssertEqual(presented, 0)

        pointer = point(in: screen.frame, corner: .bottomRight)
        coordinator.refreshPresence()
        XCTAssertEqual(scheduler.tokens.count, 2)
        now = 20.800
        scheduler.fire(1)

        XCTAssertEqual(presented, 1)
    }

    func testUpdatingCornerPreservesOpenAndClosingLifecycleForReentry() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = point(in: screen.frame, corner: .topLeft)
        let scheduler = ManualDeadlineScheduler()
        var reversed = 0
        let coordinator = makeCoordinator(
            screen: screen,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler,
            reverse: { _ in reversed += 1 }
        )
        XCTAssertTrue(coordinator.start())
        now = 20.400
        scheduler.fire(0)
        coordinator.panelBeganOpening()
        coordinator.panelDidOpen()

        coordinator.updateCorner(.bottomRight)
        coordinator.panelBeganClosing()
        pointer = point(in: screen.frame, corner: .bottomRight)
        now = 21
        coordinator.refreshPresence()

        XCTAssertEqual(reversed, 1)
    }

    func testStartCreatesExactMainScreenTopLeftPanelsAndStopOrdersThemOut() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var pointer = CGPoint(x: screen.frame.maxX - 100, y: screen.frame.minY + 100)
        let coordinator = makeCoordinator(
            screen: screen,
            pointer: { pointer }
        )

        XCTAssertTrue(coordinator.start())
        let frames = TriggerZonePanel.frames(for: screen.frame, corner: .topLeft)
        XCTAssertEqual(coordinator.horizontalPanel?.frame, frames.horizontal)
        XCTAssertEqual(coordinator.verticalPanel?.frame, frames.vertical)
        XCTAssertTrue(coordinator.horizontalPanel?.isVisible == true)
        XCTAssertTrue(coordinator.verticalPanel?.isVisible == true)

        coordinator.stop()

        XCTAssertFalse(coordinator.horizontalPanel?.isVisible == true)
        XCTAssertFalse(coordinator.verticalPanel?.isVisible == true)
        pointer = .zero
    }

    func testBoundarySamplesInjectedPointerAndSchedulesFourHundredMilliseconds() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = horizontalExclusivePoint(in: screen.frame)
        let scheduler = ManualDeadlineScheduler()
        var triggerPresence: [Bool] = []
        let coordinator = makeCoordinator(
            screen: screen,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler
        )
        coordinator.onTriggerPresenceChanged = { triggerPresence.append($0) }
        XCTAssertTrue(coordinator.start())

        coordinator.horizontalPanel?.trackingView.onBoundaryChanged()

        XCTAssertEqual(scheduler.scheduledDelays.count, 1)
        XCTAssertEqual(scheduler.scheduledDelays[0], 0.400, accuracy: 0.0000001)
        XCTAssertTrue(triggerPresence.contains(true))
        now = 20.400
        pointer = horizontalExclusivePoint(in: screen.frame)
    }

    func testMovingBetweenArmFramesDoesNotReplaceTheDwellToken() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = horizontalExclusivePoint(in: screen.frame)
        let scheduler = ManualDeadlineScheduler()
        let coordinator = makeCoordinator(
            screen: screen,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler
        )
        XCTAssertTrue(coordinator.start())

        coordinator.horizontalPanel?.trackingView.onBoundaryChanged()
        pointer = verticalExclusivePoint(in: screen.frame)
        now = 20.250
        coordinator.verticalPanel?.trackingView.onBoundaryChanged()

        XCTAssertEqual(scheduler.scheduledDelays.count, 1)
        XCTAssertFalse(scheduler.tokens[0].isCancelled)
    }

    func testDwellFireRechecksPointerBeforePresenting() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = horizontalExclusivePoint(in: screen.frame)
        let scheduler = ManualDeadlineScheduler()
        var presented = 0
        let coordinator = makeCoordinator(
            screen: screen,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler,
            present: { _ in presented += 1 }
        )
        XCTAssertTrue(coordinator.start())
        coordinator.horizontalPanel?.trackingView.onBoundaryChanged()

        pointer = outsidePoint(in: screen.frame)
        now = 20.400
        scheduler.fire(0)

        XCTAssertEqual(presented, 0)
    }

    func testTriggerStillPresentsAndReversesWithoutOwningPanelDismissal() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = horizontalExclusivePoint(in: screen.frame)
        let scheduler = ManualDeadlineScheduler()
        var presented = 0
        var reversed = 0
        let coordinator = makeCoordinator(
            screen: screen,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler,
            present: { _ in presented += 1 },
            reverse: { _ in reversed += 1 }
        )
        XCTAssertTrue(coordinator.start())
        coordinator.horizontalPanel?.trackingView.onBoundaryChanged()
        now = 20.400
        scheduler.fire(0)
        coordinator.panelBeganOpening()
        coordinator.panelDidOpen()

        coordinator.panelBeganClosing()
        pointer = horizontalExclusivePoint(in: screen.frame)
        now = 21
        coordinator.refreshPresence()

        XCTAssertEqual(presented, 1)
        XCTAssertEqual(reversed, 1)
    }

    func testLeavingAnOpenPanelOnlyPublishesTriggerPresence() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var now: TimeInterval = 20
        var pointer = horizontalExclusivePoint(in: screen.frame)
        let scheduler = ManualDeadlineScheduler()
        var presence: [Bool] = []
        let coordinator = makeCoordinator(
            screen: screen,
            now: { now },
            pointer: { pointer },
            scheduler: scheduler
        )
        coordinator.onTriggerPresenceChanged = { presence.append($0) }
        XCTAssertTrue(coordinator.start())
        coordinator.horizontalPanel?.trackingView.onBoundaryChanged()
        now = 20.400
        scheduler.fire(0)
        coordinator.panelBeganOpening()
        coordinator.panelDidOpen()

        pointer = outsidePoint(in: screen.frame)
        now = 21
        coordinator.refreshPresence()

        XCTAssertEqual(scheduler.scheduledDelays.count, 1)
        XCTAssertEqual(presence.last, false)
    }

    func testStartAndStopAreIdempotentAndStopCancelsDwell() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let scheduler = ManualDeadlineScheduler()
        let pointer = horizontalExclusivePoint(in: screen.frame)
        let coordinator = makeCoordinator(
            screen: screen,
            pointer: { pointer },
            scheduler: scheduler
        )

        XCTAssertTrue(coordinator.start())
        XCTAssertTrue(coordinator.start())
        coordinator.horizontalPanel?.trackingView.onBoundaryChanged()
        coordinator.stop()
        coordinator.stop()

        XCTAssertTrue(scheduler.tokens.allSatisfy(\.isCancelled))
        XCTAssertFalse(coordinator.isRunning)
    }

    private func makeCoordinator(
        screen: NSScreen,
        corner: TriggerCorner = .topLeft,
        now: @escaping @MainActor () -> TimeInterval = { 0 },
        pointer: @escaping @MainActor () -> CGPoint,
        scheduler: ManualDeadlineScheduler = ManualDeadlineScheduler(),
        present: @escaping (UInt32) -> Void = { _ in },
        reverse: @escaping (UInt32) -> Void = { _ in }
    ) -> CornerTriggerCoordinator {
        CornerTriggerCoordinator(
            screenProvider: { screen },
            corner: corner,
            clock: now,
            pointerLocationProvider: pointer,
            scheduler: scheduler,
            presentPanel: present,
            reverseClosingPanel: reverse
        )
    }

    private func horizontalExclusivePoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + 30, y: frame.maxY - 10)
    }

    private func verticalExclusivePoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + 10, y: frame.maxY - 30)
    }

    private func outsidePoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    private func point(in frame: CGRect, corner: TriggerCorner) -> CGPoint {
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

final class TriggerCornerStoreTests: XCTestCase {
    func testDefaultsToTopLeftAndPersistsEveryCornerAcrossFreshAdapters() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(TriggerCornerStore(defaults: defaults).load(), .topLeft)

        for corner in TriggerCorner.allCases {
            TriggerCornerStore(defaults: defaults).save(corner)
            XCTAssertEqual(TriggerCornerStore(defaults: defaults).load(), corner)
        }
    }

    func testInvalidPersistedValueFallsBackToTopLeft() {
        let defaults = isolatedDefaults()
        defaults.set("sideways", forKey: TriggerCornerStore.storageKey)

        XCTAssertEqual(TriggerCornerStore(defaults: defaults).load(), .topLeft)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CornerPet.TriggerCornerStoreTests.\(UUID().uuidString)")!
    }
}

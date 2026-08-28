import XCTest

@testable import CornerPet

final class HotCornerStateMachineTests: XCTestCase {
    private let outside = HotCornerPointerPresence(
        isInsideTrigger: false,
        isInsidePanel: false
    )
    private let inTrigger = HotCornerPointerPresence(
        isInsideTrigger: true,
        isInsidePanel: false
    )

    func testDwellPresentsOnceAtExactlyFourHundredMilliseconds() throws {
        var machine = HotCornerStateMachine()
        let deadline = try XCTUnwrap(
            machine.handle(.presenceChanged(inTrigger, at: 10)).scheduledDeadline
        )

        XCTAssertEqual(
            machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.399)),
            []
        )
        XCTAssertEqual(
            machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400)),
            [.present]
        )
        XCTAssertEqual(machine.state, .opening)
    }

    func testLeavingBeforeDwellCancelsAndStaleDeadlineCannotPresent() throws {
        var machine = HotCornerStateMachine()
        let deadline = try XCTUnwrap(
            machine.handle(.presenceChanged(inTrigger, at: 10)).scheduledDeadline
        )

        XCTAssertEqual(machine.handle(.presenceChanged(outside, at: 10.200)), [.cancelDeadline])
        XCTAssertEqual(
            machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400)),
            []
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testMovingBetweenTriggerArmsPreservesOriginalDwellDeadline() throws {
        var machine = HotCornerStateMachine()
        let deadline = try XCTUnwrap(
            machine.handle(.presenceChanged(inTrigger, at: 10)).scheduledDeadline
        )
        let otherArm = HotCornerPointerPresence(isInsideTrigger: true, isInsidePanel: false)

        XCTAssertEqual(machine.handle(.presenceChanged(otherArm, at: 10.250)), [])
        XCTAssertEqual(machine.nextDeadline, deadline)
        XCTAssertEqual(
            machine.handle(.deadlineReached(deadline, presence: otherArm, at: 10.400)),
            [.present]
        )
    }

    func testPanelBeginningToOpenCancelsAnyPendingDwell() throws {
        var machine = HotCornerStateMachine()
        let deadline = try XCTUnwrap(
            machine.handle(.presenceChanged(inTrigger, at: 10)).scheduledDeadline
        )

        XCTAssertEqual(
            machine.handle(.panelBeganOpening(at: 10.100)),
            [.cancelDeadline]
        )
        XCTAssertEqual(machine.state, .opening)
        XCTAssertNil(machine.nextDeadline)
        XCTAssertEqual(
            machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400)),
            []
        )
    }

    func testTriggerReducerNeverOwnsAnOpenPanelDeadline() {
        var machine = HotCornerStateMachine()
        _ = machine.handle(.presenceChanged(inTrigger, at: 10))
        _ = machine.handle(.deadlineReached(
            HotCornerDeadline(generation: 1, dueAt: 10.400),
            presence: inTrigger,
            at: 10.400
        ))
        _ = machine.handle(.panelBeganOpening(at: 10.401))
        _ = machine.handle(.panelDidOpen(at: 10.661))

        XCTAssertEqual(machine.handle(.presenceChanged(outside, at: 20)), [])
        XCTAssertNil(machine.nextDeadline)
        XCTAssertEqual(machine.state, .open)
    }

    func testClosingReentryRequestsOneReverse() {
        var machine = HotCornerStateMachine()
        _ = machine.handle(.presenceChanged(inTrigger, at: 10))
        let deadline = HotCornerDeadline(generation: 1, dueAt: 10.400)
        _ = machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400))
        _ = machine.handle(.panelDidOpen(at: 10.500))
        _ = machine.handle(.panelBeganClosing(at: 11))

        XCTAssertEqual(machine.handle(.presenceChanged(inTrigger, at: 11.010)), [.reverseClosing])
        XCTAssertEqual(machine.handle(.presenceChanged(inTrigger, at: 11.020)), [])
    }

    func testClosingReentryTransitionsBackThroughOpeningBeforeTheNextClose() {
        var machine = HotCornerStateMachine()
        _ = machine.handle(.presenceChanged(inTrigger, at: 10))
        let deadline = HotCornerDeadline(generation: 1, dueAt: 10.400)
        _ = machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400))
        _ = machine.handle(.panelDidOpen(at: 10.500))
        _ = machine.handle(.panelBeganClosing(at: 11))
        _ = machine.handle(.presenceChanged(inTrigger, at: 11.010))

        _ = machine.handle(.panelBeganOpening(at: 11.020))
        XCTAssertEqual(machine.state, .opening)
        _ = machine.handle(.panelDidOpen(at: 11.280))
        XCTAssertEqual(machine.state, .open)

        _ = machine.handle(.panelBeganClosing(at: 12))
        XCTAssertEqual(machine.state, .closing(reverseRequested: false))
        _ = machine.handle(.panelDidClose(at: 12.180))
        XCTAssertEqual(machine.state, .suppressedUntilTriggerExit)
    }

    func testCloseCompletionRecoversEvenWhenARequestedReverseDoesNotComplete() {
        var machine = HotCornerStateMachine()
        _ = machine.handle(.presenceChanged(inTrigger, at: 10))
        let deadline = HotCornerDeadline(generation: 1, dueAt: 10.400)
        _ = machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400))
        _ = machine.handle(.panelDidOpen(at: 10.500))
        _ = machine.handle(.panelBeganClosing(at: 11))
        _ = machine.handle(.presenceChanged(inTrigger, at: 11.010))

        _ = machine.handle(.panelDidClose(at: 11.180))

        XCTAssertEqual(machine.state, .suppressedUntilTriggerExit)
        _ = machine.handle(.presenceChanged(outside, at: 11.200))
        XCTAssertEqual(machine.state, .idle)
    }

    func testCloseLifecycleSuppressesImmediateReopenUntilTriggerExit() {
        var machine = HotCornerStateMachine()
        _ = machine.handle(.presenceChanged(inTrigger, at: 10))
        let deadline = HotCornerDeadline(generation: 1, dueAt: 10.400)
        _ = machine.handle(.deadlineReached(deadline, presence: inTrigger, at: 10.400))
        _ = machine.handle(.panelDidOpen(at: 10.500))
        _ = machine.handle(.panelBeganClosing(at: 11))
        _ = machine.handle(.panelDidClose(at: 11.180))

        XCTAssertEqual(machine.state, .suppressedUntilTriggerExit)
        XCTAssertEqual(machine.handle(.presenceChanged(inTrigger, at: 11.200)), [])
        XCTAssertEqual(machine.handle(.presenceChanged(outside, at: 11.220)), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testBackwardAndNonFiniteTimeNeverPresent() throws {
        var machine = HotCornerStateMachine()
        let deadline = try XCTUnwrap(
            machine.handle(.presenceChanged(inTrigger, at: 10)).scheduledDeadline
        )

        XCTAssertEqual(machine.handle(.presenceChanged(inTrigger, at: 9)), [])
        if case .dwelling = machine.state {
            // A stale sample must not corrupt an active dwell.
        } else {
            XCTFail("A backward timestamp must preserve the active dwell")
        }
        XCTAssertEqual(
            machine.handle(.deadlineReached(deadline, presence: inTrigger, at: .infinity)),
            []
        )
        XCTAssertEqual(machine.handle(.presenceChanged(inTrigger, at: .nan)), [])
    }
}

private extension Array where Element == HotCornerEffect {
    var scheduledDeadline: HotCornerDeadline? {
        compactMap { effect in
            guard case let .schedule(deadline) = effect else { return nil }
            return deadline
        }.first
    }
}

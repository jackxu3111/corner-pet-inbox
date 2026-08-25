import CoreGraphics
import XCTest

@testable import CornerPet

final class HotCornerStateMachineTests: XCTestCase {
    func testDefaultPresetIsStandard() {
        XCTAssertEqual(DwellPreset.default, .standard)
    }

    func testFastPresetRequiresExactly500Milliseconds() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .fast)
        let target = makeTarget()

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.499, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.5, targets: [target])),
            .present(screenID: target.screenID)
        )
    }

    func testStandardPresetRequiresExactly600Milliseconds() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget()

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.599, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.6, targets: [target])),
            .present(screenID: target.screenID)
        )
    }

    func testConservativePresetRequiresExactly700Milliseconds() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .conservative)
        let target = makeTarget()

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.699, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.7, targets: [target])),
            .present(screenID: target.screenID)
        )
    }

    func testMovingBetweenArmsPreservesTheOriginalDwellStart() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(
            regions: [
                CGRect(x: 0, y: 0, width: 43, height: 6),
                CGRect(x: 0, y: 0, width: 6, height: 43)
            ]
        )

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 20, y: 3), at: 0, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 3, y: 20), at: 0.599, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 3, y: 20), at: 0.6, targets: [target])),
            .present(screenID: target.screenID)
        )
    }

    func testLeavingTheCombinedRegionsResetsAndReentryStartsANewDwell() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget()

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 20, y: 20), at: 0.599, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .idle)
        XCTAssertNil(stateMachine.nextEvaluationDeadline)

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.599, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.6, targets: [target])),
            .present(screenID: target.screenID)
        )
    }

    func testPresentationIsRequestedOnlyOnceUntilTheLifecycleChanges() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget()

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.6, targets: [target])),
            .present(screenID: target.screenID)
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.2, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .presentRequested(screenID: target.screenID))
        XCTAssertNil(stateMachine.nextEvaluationDeadline)
    }

    func testChangingScreenCornerOrRegionsRestartsTheDwell() {
        let original = makeTarget(screenID: 1, corner: .topLeft)
        let variants = [
            makeTarget(screenID: 2, corner: .topLeft),
            makeTarget(screenID: 1, corner: .bottomRight),
            makeTarget(
                screenID: 1,
                corner: .topLeft,
                regions: [CGRect(x: 0, y: 0, width: 7, height: 6)]
            )
        ]

        for variant in variants {
            var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
            XCTAssertEqual(
                stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [original])),
                .none
            )
            XCTAssertEqual(
                stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.3, targets: [variant])),
                .none
            )
            XCTAssertEqual(
                stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.899, targets: [variant])),
                .none
            )
            XCTAssertEqual(
                stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.9, targets: [variant])),
                .present(screenID: variant.screenID)
            )
        }
    }

    func testOverlappingTargetsPreferCurrentDwellingTargetBeforeProviderOrder() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let first = makeTarget(screenID: 1)
        let second = makeTarget(screenID: 2)

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [first, second])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.599, targets: [second, first])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.6, targets: [second, first])),
            .present(screenID: first.screenID)
        )
    }

    func testClosingOnTheTriggerScreenReversesImmediatelyAndOnlyOnce() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        moveStateMachineToOpen(&stateMachine, target: target)

        XCTAssertEqual(
            stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .closing(screenID: 1, reverseRequested: false))

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.001, targets: [target])),
            .reverseClosing(screenID: 1)
        )
        XCTAssertEqual(stateMachine.state, .closing(screenID: 1, reverseRequested: true))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.002, targets: [target])),
            .none
        )
    }

    func testClosingOnAnotherScreenDoesNotReverseTheCurrentPanel() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let currentTarget = makeTarget(screenID: 1)
        let otherTarget = makeTarget(screenID: 2)
        moveStateMachineToOpen(&stateMachine, target: currentTarget)

        _ = stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.001, targets: [otherTarget])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .closing(screenID: 1, reverseRequested: false))
    }

    func testLifecycleStatesSuppressPointerActions() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.6, targets: [target])),
            .present(screenID: 1)
        )
        XCTAssertEqual(
            stateMachine.handle(.panelBeganOpening(screenID: 1, at: 0.61)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .opening(screenID: 1))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.7, targets: [target])),
            .none
        )

        XCTAssertEqual(
            stateMachine.handle(.panelDidOpen(screenID: 1, at: 0.87)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .open(screenID: 1))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.9, targets: [target])),
            .none
        )

        XCTAssertEqual(
            stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .closing(screenID: 1, reverseRequested: false))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 20, y: 20), at: 1.01, targets: [target])),
            .none
        )
    }

    func testReversingAClosingPanelCanEnterOpeningStateAgain() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        moveStateMachineToOpen(&stateMachine, target: target)

        _ = stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.001, targets: [target])),
            .reverseClosing(screenID: 1)
        )
        XCTAssertEqual(
            stateMachine.handle(.panelBeganOpening(screenID: 1, at: 1.002)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .opening(screenID: 1))
    }

    func testLatePanelDidCloseCannotReplaceOpeningAfterReverse() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        moveStateMachineToOpen(&stateMachine, target: target)

        _ = stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.001, targets: [target])),
            .reverseClosing(screenID: 1)
        )
        _ = stateMachine.handle(.panelBeganOpening(screenID: 1, at: 1.002))
        XCTAssertEqual(stateMachine.state, .opening(screenID: 1))

        XCTAssertEqual(
            stateMachine.handle(.panelDidClose(at: 1.003)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .opening(screenID: 1))
        XCTAssertNil(stateMachine.nextEvaluationDeadline)

        _ = stateMachine.handle(.panelDidOpen(screenID: 1, at: 1.004))
        XCTAssertEqual(stateMachine.state, .open(screenID: 1))
    }

    func testPanelDidCloseStartsAn80MillisecondDebounceBeforeAFullDwell() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        moveStateMachineToOpen(&stateMachine, target: target)
        _ = stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1))

        XCTAssertEqual(
            stateMachine.handle(.panelDidClose(at: 10)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .postCloseDebounce(until: 10.08))
        XCTAssertEqual(stateMachine.nextEvaluationDeadline, 10.08)

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 10.079, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .postCloseDebounce(until: 10.08))

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 10.08, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .dwelling(target: target, enteredAt: 10.08))
        XCTAssertEqual(stateMachine.nextEvaluationDeadline, 10.68)
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 10.679, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 10.68, targets: [target])),
            .present(screenID: 1)
        )
    }

    func testPanelDidCloseOutsideClosingLifecycleIsIgnored() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.panelDidClose(at: 0.3)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .dwelling(target: target, enteredAt: 0))
        XCTAssertEqual(stateMachine.nextEvaluationDeadline, 0.6)
    }

    func testADeadlineThatWasCancelledByLeavingCannotPresentLater() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 20, y: 20), at: 0.3, targets: [target])),
            .none
        )
        XCTAssertNil(stateMachine.nextEvaluationDeadline)
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 20, y: 20), at: 0.6, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testBackwardTimeInvalidatesDwellWithoutPresentingEarly() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1, targets: [target]))
        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.2, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.1, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .idle)
        XCTAssertNil(stateMachine.nextEvaluationDeadline)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 1.5, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 2.099, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 2.1, targets: [target])),
            .present(screenID: 1)
        )
    }

    func testNonFinitePointerTimeInvalidatesDwell() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: .nan, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .idle)
        XCTAssertNil(stateMachine.nextEvaluationDeadline)
    }

    func testDwellDeadlineOverflowSafelyRejectsTheSampleAndCanRecover() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        let largestFiniteTime = Double.greatestFiniteMagnitude

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(
                location: CGPoint(x: 1, y: 1),
                at: largestFiniteTime,
                targets: [target]
            )),
            .none
        )
        XCTAssertEqual(stateMachine.state, .idle)
        XCTAssertNil(stateMachine.nextEvaluationDeadline)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(stateMachine.state, .dwelling(target: target, enteredAt: 0))
        XCTAssertEqual(stateMachine.nextEvaluationDeadline, 0.6)
    }

    func testPostCloseDebounceOverflowSafelyRejectsTheSampleAndCanRecover() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        let largestFiniteTime = Double.greatestFiniteMagnitude
        moveStateMachineToOpen(&stateMachine, target: target)

        _ = stateMachine.handle(.panelBeganClosing(screenID: 1, at: 1))
        XCTAssertEqual(
            stateMachine.handle(.panelDidClose(at: largestFiniteTime)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .idle)
        XCTAssertNil(stateMachine.nextEvaluationDeadline)

        _ = stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target]))
        XCTAssertEqual(stateMachine.state, .dwelling(target: target, enteredAt: 0))
        XCTAssertEqual(stateMachine.nextEvaluationDeadline, 0.6)
    }

    func testInvalidTimeDoesNotDestroyAnOpenLifecycleState() {
        var stateMachine = HotCornerStateMachine(dwellPreset: .standard)
        let target = makeTarget(screenID: 1)
        moveStateMachineToOpen(&stateMachine, target: target)

        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: -.infinity, targets: [target])),
            .none
        )
        XCTAssertEqual(stateMachine.state, .open(screenID: 1))
        XCTAssertEqual(
            stateMachine.handle(.panelDidClose(at: .infinity)),
            .none
        )
        XCTAssertEqual(stateMachine.state, .open(screenID: 1))
    }

    private func makeTarget(
        screenID: UInt32 = 42,
        corner: TriggerCorner = .topLeft,
        regions: [CGRect] = [CGRect(x: 0, y: 0, width: 6, height: 6)]
    ) -> HotCornerTarget {
        HotCornerTarget(
            screenID: screenID,
            corner: corner,
            regions: regions
        )
    }

    private func moveStateMachineToOpen(
        _ stateMachine: inout HotCornerStateMachine,
        target: HotCornerTarget
    ) {
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0, targets: [target])),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.pointerObserved(location: CGPoint(x: 1, y: 1), at: 0.6, targets: [target])),
            .present(screenID: target.screenID)
        )
        XCTAssertEqual(
            stateMachine.handle(.panelBeganOpening(screenID: target.screenID, at: 0.61)),
            .none
        )
        XCTAssertEqual(
            stateMachine.handle(.panelDidOpen(screenID: target.screenID, at: 0.87)),
            .none
        )
    }
}

@MainActor
final class MouseMonitorTests: XCTestCase {
    func testStartAndStopAreIdempotent() {
        let monitor = MouseMonitor(
            dwellPreset: .standard,
            clock: { 0 },
            targetsProvider: { [] },
            actionHandler: { _ in }
        )

        XCTAssertTrue(monitor.start())
        XCTAssertTrue(monitor.start())
        XCTAssertTrue(monitor.isRunning)

        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }
}

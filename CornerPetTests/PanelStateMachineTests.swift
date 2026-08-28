import XCTest

@testable import CornerPet

final class PanelStateMachineTests: XCTestCase {
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
    private let editing = PanelContentStatus(
        hasDraft: false,
        hasItemEdit: true,
        hasError: false
    )
    private let errorWhileEditing = PanelContentStatus(
        hasDraft: false,
        hasItemEdit: true,
        hasError: true
    )

    func testPresentTransitionsHiddenOpeningOpenEmpty() {
        var machine = PanelStateMachine()

        XCTAssertEqual(machine.handle(.presentRequested), [.present])
        XCTAssertEqual(machine.state, .opening)

        XCTAssertEqual(
            machine.handle(.didOpen(content: empty, pointerInsideKeepOpen: true)),
            []
        )
        XCTAssertEqual(machine.state, .openEmpty)
    }

    func testDraftAndEditExitNeverScheduleClose() {
        for content in [draft, editing] {
            var machine = makeOpenMachine(content: content)

            XCTAssertEqual(
                machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 20)),
                []
            )
            XCTAssertNil(machine.nextDeadline)
            XCTAssertEqual(machine.state, content == draft ? .draftLocked : .itemEditing)
        }
    }

    func testOpenEmptyExitSchedulesExactly120Milliseconds() throws {
        var machine = makeOpenMachine(content: empty)

        let effects = machine.handle(
            .pointerChanged(isInsideKeepOpen: false, at: 20)
        )
        let deadline = try XCTUnwrap(effects.scheduledDeadline)

        XCTAssertEqual(deadline.generation, 1)
        XCTAssertEqual(deadline.dueAt, 20.120, accuracy: 0.0000001)
        XCTAssertEqual(machine.nextDeadline, deadline)
    }

    func testReentryCancelsAndStaleDeadlineCannotClose() throws {
        var machine = makeOpenMachine(content: empty)
        let deadline = try XCTUnwrap(
            machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 20)).scheduledDeadline
        )

        XCTAssertEqual(
            machine.handle(.pointerChanged(isInsideKeepOpen: true, at: 20.050)),
            [.cancelDeadline]
        )
        XCTAssertEqual(
            machine.handle(
                .exitDeadlineReached(deadline, isInsideKeepOpen: false, at: 20.120)
            ),
            []
        )
        XCTAssertEqual(machine.state, .openEmpty)
    }

    func testErrorIgnoresExitAndExternalFocus() {
        var machine = makeOpenMachine(content: errorWhileEditing)

        XCTAssertEqual(machine.state, .error)
        XCTAssertEqual(
            machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 30)),
            []
        )
        XCTAssertEqual(
            machine.handle(.externalFocusLost(editSaveSucceeded: nil)),
            []
        )
        XCTAssertEqual(machine.state, .error)
        XCTAssertNil(machine.nextDeadline)
    }

    func testPinnedIgnoresExitAndExternalFocus() {
        var machine = makeOpenMachine(content: empty)
        XCTAssertEqual(
            machine.handle(.pinToggled(pointerInsideKeepOpen: true)),
            [.setPinned(true)]
        )
        XCTAssertEqual(machine.state, .pinned)

        XCTAssertEqual(
            machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 40)),
            []
        )
        XCTAssertEqual(
            machine.handle(.externalFocusLost(editSaveSucceeded: nil)),
            []
        )
        XCTAssertEqual(machine.state, .pinned)
    }

    func testExternalFocusClosesDraftPreservingContent() {
        var machine = makeOpenMachine(content: draft)

        XCTAssertEqual(
            machine.handle(.externalFocusLost(editSaveSucceeded: nil)),
            [.dismiss]
        )
        XCTAssertEqual(machine.state, .closing)
    }

    func testExternalFocusEditSuccessClosesAndFailureStaysEditingInError() {
        var machine = makeOpenMachine(content: editing)

        XCTAssertEqual(
            machine.handle(.externalFocusLost(editSaveSucceeded: false)),
            []
        )
        XCTAssertEqual(machine.state, .error)

        XCTAssertEqual(
            machine.handle(.contentChanged(editing, pointerInsideKeepOpen: true)),
            []
        )
        XCTAssertEqual(machine.state, .itemEditing)

        XCTAssertEqual(
            machine.handle(.externalFocusLost(editSaveSucceeded: true)),
            [.dismiss]
        )
        XCTAssertEqual(machine.state, .closing)
    }

    func testUnpinDraftOrEditReturnsToCornerAndStaysOpen() {
        for content in [draft, editing] {
            var machine = makeOpenMachine(content: content)
            XCTAssertEqual(
                machine.handle(.pinToggled(pointerInsideKeepOpen: false)),
                [.setPinned(true)]
            )

            XCTAssertEqual(
                machine.handle(.pinToggled(pointerInsideKeepOpen: false)),
                [.setPinned(false), .returnToCorner]
            )
            XCTAssertEqual(
                machine.handle(.didReturnToCorner(pointerInsideKeepOpen: false)),
                []
            )
            XCTAssertEqual(machine.state, content == draft ? .draftLocked : .itemEditing)
        }
    }

    func testUnpinEmptyOutsideReturnsThenCloses() {
        var machine = makeOpenMachine(content: empty)
        _ = machine.handle(.pinToggled(pointerInsideKeepOpen: true))

        XCTAssertEqual(
            machine.handle(.pinToggled(pointerInsideKeepOpen: false)),
            [.setPinned(false), .returnToCorner]
        )
        XCTAssertEqual(machine.state, .openEmpty)
        XCTAssertEqual(
            machine.handle(.didReturnToCorner(pointerInsideKeepOpen: false)),
            [.dismiss]
        )
        XCTAssertEqual(machine.state, .closing)
    }

    func testReentryDuringUnpinReturnReopensAnEmptyPanel() {
        var machine = makeOpenMachine(content: empty)
        _ = machine.handle(.pinToggled(pointerInsideKeepOpen: true))
        _ = machine.handle(.pinToggled(pointerInsideKeepOpen: false))
        _ = machine.handle(.closeRequested)

        XCTAssertEqual(
            machine.handle(.pointerChanged(isInsideKeepOpen: true, at: 50)),
            [.reverseClosing]
        )
        XCTAssertEqual(
            machine.handle(.didReturnToCorner(pointerInsideKeepOpen: true)),
            []
        )
        XCTAssertEqual(machine.state, .openEmpty)
    }

    func testClosingReentryEmitsOneReverse() {
        var machine = makeOpenMachine(content: empty)
        XCTAssertEqual(machine.handle(.closeRequested), [.dismiss])
        XCTAssertEqual(machine.state, .closing)

        XCTAssertEqual(
            machine.handle(.pointerChanged(isInsideKeepOpen: true, at: 50)),
            [.reverseClosing]
        )
        XCTAssertEqual(
            machine.handle(.pointerChanged(isInsideKeepOpen: true, at: 50.010)),
            []
        )
    }

    func testNonFiniteBackwardAndEarlyDeadlineNeverClose() throws {
        var machine = makeOpenMachine(content: empty)
        let deadline = try XCTUnwrap(
            machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 60)).scheduledDeadline
        )

        XCTAssertEqual(
            machine.handle(
                .exitDeadlineReached(deadline, isInsideKeepOpen: false, at: 60.119)
            ),
            []
        )
        XCTAssertEqual(machine.state, .openEmpty)
        XCTAssertEqual(
            machine.handle(
                .exitDeadlineReached(deadline, isInsideKeepOpen: false, at: .nan)
            ),
            []
        )
        XCTAssertEqual(machine.state, .openEmpty)

        var backwards = makeOpenMachine(content: empty)
        let backwardsDeadline = try XCTUnwrap(
            backwards.handle(.pointerChanged(isInsideKeepOpen: false, at: 70)).scheduledDeadline
        )
        XCTAssertEqual(
            backwards.handle(
                .exitDeadlineReached(backwardsDeadline, isInsideKeepOpen: false, at: 69)
            ),
            []
        )
        XCTAssertEqual(backwards.state, .openEmpty)

        var stable = makeOpenMachine(content: empty)
        let stableDeadline = try XCTUnwrap(
            stable.handle(.pointerChanged(isInsideKeepOpen: false, at: 70)).scheduledDeadline
        )
        XCTAssertEqual(
            stable.handle(.pointerChanged(isInsideKeepOpen: false, at: .nan)),
            []
        )
        XCTAssertEqual(stable.state, .openEmpty)
        XCTAssertEqual(stable.nextDeadline, stableDeadline)
    }

    func testDidCloseReturnsToHiddenAndInvalidatesTheGeneration() throws {
        var machine = makeOpenMachine(content: empty)
        let deadline = try XCTUnwrap(
            machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 80)).scheduledDeadline
        )
        _ = machine.handle(.exitDeadlineReached(deadline, isInsideKeepOpen: false, at: 80.120))
        XCTAssertEqual(machine.handle(.didClose), [])
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertNil(machine.nextDeadline)
    }

    func testDidCloseCancelsAnOutstandingEmptyExitDeadline() throws {
        var machine = makeOpenMachine(content: empty)
        _ = machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 80))

        XCTAssertEqual(machine.handle(.didClose), [.cancelDeadline])
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertNil(machine.nextDeadline)
    }

    func testKeyStateEventMatrixKeepsInvalidEventsLazy() {
        struct MatrixCase {
            let name: String
            let makeMachine: () -> PanelStateMachine
            let event: PanelEvent
            let expectedState: PanelState
            let expectedEffects: [PanelEffect]
            let expectedDeadline: PanelDeadline?
        }

        let hidden: () -> PanelStateMachine = { PanelStateMachine() }
        let opening: () -> PanelStateMachine = {
            var machine = PanelStateMachine()
            _ = machine.handle(.presentRequested)
            return machine
        }
        let closing: () -> PanelStateMachine = {
            var machine = PanelStateMachine()
            _ = machine.handle(.presentRequested)
            _ = machine.handle(.didOpen(content: self.empty, pointerInsideKeepOpen: true))
            _ = machine.handle(.closeRequested)
            return machine
        }
        let reversingClosing: () -> PanelStateMachine = {
            var machine = closing()
            _ = machine.handle(.pointerChanged(isInsideKeepOpen: true, at: 10))
            return machine
        }
        let openEmpty: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.empty)
        }
        let draftLocked: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.draft)
        }
        let itemEditing: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.editing)
        }
        let pinned: () -> PanelStateMachine = {
            var machine = self.makeOpenMachine(content: self.empty)
            _ = machine.handle(.pinToggled(pointerInsideKeepOpen: true))
            return machine
        }
        let error: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.errorWhileEditing)
        }

        let cases: [MatrixCase] = [
            MatrixCase(
                name: "hidden pointer exit",
                makeMachine: hidden,
                event: .pointerChanged(isInsideKeepOpen: false, at: 10),
                expectedState: .hidden,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "hidden external focus",
                makeMachine: hidden,
                event: .externalFocusLost(editSaveSucceeded: false),
                expectedState: .hidden,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "hidden pin shortcut",
                makeMachine: hidden,
                event: .pinToggled(pointerInsideKeepOpen: true),
                expectedState: .hidden,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "opening pointer exit",
                makeMachine: opening,
                event: .pointerChanged(isInsideKeepOpen: false, at: 10),
                expectedState: .opening,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "opening external focus",
                makeMachine: opening,
                event: .externalFocusLost(editSaveSucceeded: false),
                expectedState: .opening,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "opening pin shortcut",
                makeMachine: opening,
                event: .pinToggled(pointerInsideKeepOpen: true),
                expectedState: .opening,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "opening stale return callback",
                makeMachine: opening,
                event: .didReturnToCorner(pointerInsideKeepOpen: false),
                expectedState: .opening,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "open empty schedules literal deadline",
                makeMachine: openEmpty,
                event: .pointerChanged(isInsideKeepOpen: false, at: 10),
                expectedState: .openEmpty,
                expectedEffects: [.schedule(PanelDeadline(generation: 1, dueAt: 10.120))],
                expectedDeadline: PanelDeadline(generation: 1, dueAt: 10.120)
            ),
            MatrixCase(
                name: "draft locked ignores pointer exit",
                makeMachine: draftLocked,
                event: .pointerChanged(isInsideKeepOpen: false, at: 10),
                expectedState: .draftLocked,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "item editing ignores unknown focus result",
                makeMachine: itemEditing,
                event: .externalFocusLost(editSaveSucceeded: nil),
                expectedState: .itemEditing,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "pinned ignores pointer exit",
                makeMachine: pinned,
                event: .pointerChanged(isInsideKeepOpen: false, at: 10),
                expectedState: .pinned,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "error ignores focus loss",
                makeMachine: error,
                event: .externalFocusLost(editSaveSucceeded: false),
                expectedState: .error,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "closing stale didOpen callback",
                makeMachine: closing,
                event: .didOpen(content: draft, pointerInsideKeepOpen: true),
                expectedState: .closing,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "closing reversal handshake",
                makeMachine: reversingClosing,
                event: .presentRequested,
                expectedState: .opening,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "closing pointer exit",
                makeMachine: closing,
                event: .pointerChanged(isInsideKeepOpen: false, at: 10),
                expectedState: .closing,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "closing external focus",
                makeMachine: closing,
                event: .externalFocusLost(editSaveSucceeded: false),
                expectedState: .closing,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "closing pin shortcut",
                makeMachine: closing,
                event: .pinToggled(pointerInsideKeepOpen: true),
                expectedState: .closing,
                expectedEffects: [],
                expectedDeadline: nil
            ),
            MatrixCase(
                name: "closing stale return callback",
                makeMachine: closing,
                event: .didReturnToCorner(pointerInsideKeepOpen: false),
                expectedState: .closing,
                expectedEffects: [],
                expectedDeadline: nil
            )
        ]

        for testCase in cases {
            var machine = testCase.makeMachine()
            let effects = machine.handle(testCase.event)

            XCTAssertEqual(
                effects,
                testCase.expectedEffects,
                "effects for \(testCase.name)"
            )
            XCTAssertEqual(
                machine.state,
                testCase.expectedState,
                "state for \(testCase.name)"
            )
            XCTAssertEqual(
                machine.nextDeadline,
                testCase.expectedDeadline,
                "deadline for \(testCase.name)"
            )
        }
    }

    func testContentPriorityMatrixUsesIndependentExpectedStates() {
        struct ContentCase {
            let name: String
            let content: PanelContentStatus
            let expectedState: PanelState
        }

        let cases: [ContentCase] = [
            ContentCase(
                name: "empty",
                content: PanelContentStatus(hasDraft: false, hasItemEdit: false, hasError: false),
                expectedState: .openEmpty
            ),
            ContentCase(
                name: "draft",
                content: PanelContentStatus(hasDraft: true, hasItemEdit: false, hasError: false),
                expectedState: .draftLocked
            ),
            ContentCase(
                name: "edit",
                content: PanelContentStatus(hasDraft: false, hasItemEdit: true, hasError: false),
                expectedState: .itemEditing
            ),
            ContentCase(
                name: "draft and edit",
                content: PanelContentStatus(hasDraft: true, hasItemEdit: true, hasError: false),
                expectedState: .itemEditing
            ),
            ContentCase(
                name: "error",
                content: PanelContentStatus(hasDraft: false, hasItemEdit: false, hasError: true),
                expectedState: .error
            ),
            ContentCase(
                name: "error and draft",
                content: PanelContentStatus(hasDraft: true, hasItemEdit: false, hasError: true),
                expectedState: .error
            ),
            ContentCase(
                name: "error and edit",
                content: PanelContentStatus(hasDraft: false, hasItemEdit: true, hasError: true),
                expectedState: .error
            ),
            ContentCase(
                name: "error, draft, and edit",
                content: PanelContentStatus(hasDraft: true, hasItemEdit: true, hasError: true),
                expectedState: .error
            )
        ]

        for testCase in cases {
            var machine = PanelStateMachine()
            XCTAssertEqual(machine.handle(.presentRequested), [.present], testCase.name)
            XCTAssertEqual(
                machine.handle(.didOpen(
                    content: testCase.content,
                    pointerInsideKeepOpen: true
                )),
                [],
                "effects for \(testCase.name)"
            )
            XCTAssertEqual(machine.state, testCase.expectedState, testCase.name)
            XCTAssertNil(machine.nextDeadline, testCase.name)
        }
    }

    func testPinnedAndErrorKeepIndependentUnderlyingContentForRecovery() {
        let editingWithError = PanelContentStatus(
            hasDraft: false,
            hasItemEdit: true,
            hasError: true
        )
        let editingWithoutError = PanelContentStatus(
            hasDraft: false,
            hasItemEdit: true,
            hasError: false
        )
        let draftWithError = PanelContentStatus(
            hasDraft: true,
            hasItemEdit: false,
            hasError: true
        )

        var pinned = makeOpenMachine(content: empty)
        XCTAssertEqual(
            pinned.handle(.pinToggled(pointerInsideKeepOpen: true)),
            [.setPinned(true)]
        )
        XCTAssertEqual(
            pinned.handle(.contentChanged(editingWithError, pointerInsideKeepOpen: false)),
            []
        )
        XCTAssertEqual(pinned.state, .pinned)
        XCTAssertEqual(pinned.contentStatus, editingWithError)
        XCTAssertEqual(
            pinned.handle(.pinToggled(pointerInsideKeepOpen: false)),
            [.setPinned(false), .returnToCorner]
        )
        XCTAssertEqual(pinned.state, .error)
        XCTAssertEqual(
            pinned.handle(.contentChanged(editingWithoutError, pointerInsideKeepOpen: true)),
            []
        )
        XCTAssertEqual(pinned.state, .itemEditing)

        var errored = makeOpenMachine(content: editingWithoutError)
        XCTAssertEqual(
            errored.handle(.externalFocusLost(editSaveSucceeded: false)),
            []
        )
        XCTAssertEqual(errored.state, .error)
        XCTAssertEqual(
            errored.handle(.contentChanged(draftWithError, pointerInsideKeepOpen: true)),
            []
        )
        XCTAssertEqual(errored.state, .error)
        XCTAssertEqual(
            errored.handle(.contentChanged(draft, pointerInsideKeepOpen: true)),
            []
        )
        XCTAssertEqual(errored.state, .draftLocked)
    }

    func testEveryPanelStateHasAnExplicitOutcomeForEveryEventCategory() {
        struct CartesianCase {
            let stateName: String
            let eventCategory: String
            let makeMachine: () -> PanelStateMachine
            let event: PanelEvent
            let initialState: PanelState
            let expectedState: PanelState
            let expectedEffects: [PanelEffect]
            let expectedDeadline: PanelDeadline?
        }

        func row(
            _ stateName: String,
            _ eventCategory: String,
            _ initialState: PanelState,
            _ makeMachine: @escaping () -> PanelStateMachine,
            _ event: PanelEvent,
            _ expectedState: PanelState,
            _ expectedEffects: [PanelEffect],
            _ expectedDeadline: PanelDeadline?
        ) -> CartesianCase {
            CartesianCase(
                stateName: stateName,
                eventCategory: eventCategory,
                makeMachine: makeMachine,
                event: event,
                initialState: initialState,
                expectedState: expectedState,
                expectedEffects: expectedEffects,
                expectedDeadline: expectedDeadline
            )
        }

        let hidden: () -> PanelStateMachine = { PanelStateMachine() }
        let opening: () -> PanelStateMachine = {
            var machine = PanelStateMachine()
            _ = machine.handle(.presentRequested)
            return machine
        }
        let openEmpty: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.empty)
        }
        let openEmptyWithDeadline: () -> PanelStateMachine = {
            var machine = self.makeOpenMachine(content: self.empty)
            _ = machine.handle(.pointerChanged(isInsideKeepOpen: false, at: 10))
            return machine
        }
        let returnableEmpty: () -> PanelStateMachine = {
            var machine = self.makeOpenMachine(content: self.empty)
            _ = machine.handle(.pinToggled(pointerInsideKeepOpen: true))
            _ = machine.handle(.pinToggled(pointerInsideKeepOpen: false))
            return machine
        }
        let draftLocked: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.draft)
        }
        let itemEditing: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.editing)
        }
        let pinned: () -> PanelStateMachine = {
            var machine = self.makeOpenMachine(content: self.empty)
            _ = machine.handle(.pinToggled(pointerInsideKeepOpen: true))
            return machine
        }
        let error: () -> PanelStateMachine = {
            self.makeOpenMachine(content: self.errorWhileEditing)
        }
        let closing: () -> PanelStateMachine = {
            var machine = self.makeOpenMachine(content: self.empty)
            _ = machine.handle(.closeRequested)
            return machine
        }

        let cases: [CartesianCase] = [
            // hidden
            row("hidden", "presentRequested", .hidden, hidden, .presentRequested, .opening, [.present], nil),
            row("hidden", "didOpen", .hidden, hidden, .didOpen(content: empty, pointerInsideKeepOpen: true), .hidden, [], nil),
            row("hidden", "contentChanged", .hidden, hidden, .contentChanged(draft, pointerInsideKeepOpen: true), .hidden, [], nil),
            row("hidden", "pointerChanged", .hidden, hidden, .pointerChanged(isInsideKeepOpen: false, at: 10), .hidden, [], nil),
            row("hidden", "exitDeadlineReached", .hidden, hidden, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .hidden, [], nil),
            row("hidden", "externalFocusLost", .hidden, hidden, .externalFocusLost(editSaveSucceeded: false), .hidden, [], nil),
            row("hidden", "pinToggled", .hidden, hidden, .pinToggled(pointerInsideKeepOpen: true), .hidden, [], nil),
            row("hidden", "didReturnToCorner", .hidden, hidden, .didReturnToCorner(pointerInsideKeepOpen: false), .hidden, [], nil),
            row("hidden", "closeRequested", .hidden, hidden, .closeRequested, .hidden, [], nil),
            row("hidden", "didBeginClosing", .hidden, hidden, .didBeginClosing, .hidden, [], nil),
            row("hidden", "didClose", .hidden, hidden, .didClose, .hidden, [], nil),

            // opening
            row("opening", "presentRequested", .opening, opening, .presentRequested, .opening, [], nil),
            row("opening", "didOpen", .opening, opening, .didOpen(content: errorWhileEditing, pointerInsideKeepOpen: true), .error, [], nil),
            row("opening", "contentChanged", .opening, opening, .contentChanged(draft, pointerInsideKeepOpen: true), .opening, [], nil),
            row("opening", "pointerChanged", .opening, opening, .pointerChanged(isInsideKeepOpen: false, at: 10), .opening, [], nil),
            row("opening", "exitDeadlineReached", .opening, opening, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .opening, [], nil),
            row("opening", "externalFocusLost", .opening, opening, .externalFocusLost(editSaveSucceeded: false), .opening, [], nil),
            row("opening", "pinToggled", .opening, opening, .pinToggled(pointerInsideKeepOpen: true), .opening, [], nil),
            row("opening", "didReturnToCorner", .opening, opening, .didReturnToCorner(pointerInsideKeepOpen: false), .opening, [], nil),
            row("opening", "closeRequested", .opening, opening, .closeRequested, .closing, [.dismiss], nil),
            row("opening", "didBeginClosing", .opening, opening, .didBeginClosing, .closing, [], nil),
            row("opening", "didClose", .opening, opening, .didClose, .hidden, [], nil),

            // openEmpty
            row("openEmpty", "presentRequested", .openEmpty, openEmpty, .presentRequested, .openEmpty, [], nil),
            row("openEmpty", "didOpen", .openEmpty, openEmpty, .didOpen(content: draft, pointerInsideKeepOpen: true), .openEmpty, [], nil),
            row("openEmpty", "contentChanged", .openEmpty, openEmpty, .contentChanged(draft, pointerInsideKeepOpen: true), .draftLocked, [], nil),
            row("openEmpty", "pointerChanged", .openEmpty, openEmpty, .pointerChanged(isInsideKeepOpen: true, at: 10), .openEmpty, [], nil),
            row("openEmpty", "exitDeadlineReached", .openEmpty, openEmptyWithDeadline, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .closing, [.dismiss], nil),
            row("openEmpty", "externalFocusLost", .openEmpty, openEmpty, .externalFocusLost(editSaveSucceeded: nil), .closing, [.dismiss], nil),
            row("openEmpty", "pinToggled", .openEmpty, openEmpty, .pinToggled(pointerInsideKeepOpen: true), .pinned, [.setPinned(true)], nil),
            row("openEmpty", "didReturnToCorner", .openEmpty, returnableEmpty, .didReturnToCorner(pointerInsideKeepOpen: false), .closing, [.dismiss], nil),
            row("openEmpty", "closeRequested", .openEmpty, openEmpty, .closeRequested, .closing, [.dismiss], nil),
            row("openEmpty", "didBeginClosing", .openEmpty, openEmpty, .didBeginClosing, .closing, [], nil),
            row("openEmpty", "didClose", .openEmpty, openEmpty, .didClose, .hidden, [], nil),

            // draftLocked
            row("draftLocked", "presentRequested", .draftLocked, draftLocked, .presentRequested, .draftLocked, [], nil),
            row("draftLocked", "didOpen", .draftLocked, draftLocked, .didOpen(content: errorWhileEditing, pointerInsideKeepOpen: true), .draftLocked, [], nil),
            row("draftLocked", "contentChanged", .draftLocked, draftLocked, .contentChanged(errorWhileEditing, pointerInsideKeepOpen: true), .error, [], nil),
            row("draftLocked", "pointerChanged", .draftLocked, draftLocked, .pointerChanged(isInsideKeepOpen: false, at: 10), .draftLocked, [], nil),
            row("draftLocked", "exitDeadlineReached", .draftLocked, draftLocked, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .draftLocked, [], nil),
            row("draftLocked", "externalFocusLost", .draftLocked, draftLocked, .externalFocusLost(editSaveSucceeded: nil), .closing, [.dismiss], nil),
            row("draftLocked", "pinToggled", .draftLocked, draftLocked, .pinToggled(pointerInsideKeepOpen: true), .pinned, [.setPinned(true)], nil),
            row("draftLocked", "didReturnToCorner", .draftLocked, draftLocked, .didReturnToCorner(pointerInsideKeepOpen: false), .draftLocked, [], nil),
            row("draftLocked", "closeRequested", .draftLocked, draftLocked, .closeRequested, .closing, [.dismiss], nil),
            row("draftLocked", "didBeginClosing", .draftLocked, draftLocked, .didBeginClosing, .closing, [], nil),
            row("draftLocked", "didClose", .draftLocked, draftLocked, .didClose, .hidden, [], nil),

            // itemEditing
            row("itemEditing", "presentRequested", .itemEditing, itemEditing, .presentRequested, .itemEditing, [], nil),
            row("itemEditing", "didOpen", .itemEditing, itemEditing, .didOpen(content: errorWhileEditing, pointerInsideKeepOpen: true), .itemEditing, [], nil),
            row("itemEditing", "contentChanged", .itemEditing, itemEditing, .contentChanged(draft, pointerInsideKeepOpen: true), .draftLocked, [], nil),
            row("itemEditing", "pointerChanged", .itemEditing, itemEditing, .pointerChanged(isInsideKeepOpen: false, at: 10), .itemEditing, [], nil),
            row("itemEditing", "exitDeadlineReached", .itemEditing, itemEditing, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .itemEditing, [], nil),
            row("itemEditing", "externalFocusLost", .itemEditing, itemEditing, .externalFocusLost(editSaveSucceeded: false), .error, [], nil),
            row("itemEditing", "pinToggled", .itemEditing, itemEditing, .pinToggled(pointerInsideKeepOpen: true), .pinned, [.setPinned(true)], nil),
            row("itemEditing", "didReturnToCorner", .itemEditing, itemEditing, .didReturnToCorner(pointerInsideKeepOpen: false), .itemEditing, [], nil),
            row("itemEditing", "closeRequested", .itemEditing, itemEditing, .closeRequested, .closing, [.dismiss], nil),
            row("itemEditing", "didBeginClosing", .itemEditing, itemEditing, .didBeginClosing, .closing, [], nil),
            row("itemEditing", "didClose", .itemEditing, itemEditing, .didClose, .hidden, [], nil),

            // pinned
            row("pinned", "presentRequested", .pinned, pinned, .presentRequested, .pinned, [], nil),
            row("pinned", "didOpen", .pinned, pinned, .didOpen(content: draft, pointerInsideKeepOpen: true), .pinned, [], nil),
            row("pinned", "contentChanged", .pinned, pinned, .contentChanged(draft, pointerInsideKeepOpen: true), .pinned, [], nil),
            row("pinned", "pointerChanged", .pinned, pinned, .pointerChanged(isInsideKeepOpen: false, at: 10), .pinned, [], nil),
            row("pinned", "exitDeadlineReached", .pinned, pinned, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .pinned, [], nil),
            row("pinned", "externalFocusLost", .pinned, pinned, .externalFocusLost(editSaveSucceeded: false), .pinned, [], nil),
            row("pinned", "pinToggled", .pinned, pinned, .pinToggled(pointerInsideKeepOpen: false), .openEmpty, [.setPinned(false), .returnToCorner], nil),
            row("pinned", "didReturnToCorner", .pinned, pinned, .didReturnToCorner(pointerInsideKeepOpen: false), .pinned, [], nil),
            row("pinned", "closeRequested", .pinned, pinned, .closeRequested, .closing, [.dismiss], nil),
            row("pinned", "didBeginClosing", .pinned, pinned, .didBeginClosing, .closing, [], nil),
            row("pinned", "didClose", .pinned, pinned, .didClose, .hidden, [], nil),

            // error
            row("error", "presentRequested", .error, error, .presentRequested, .error, [], nil),
            row("error", "didOpen", .error, error, .didOpen(content: draft, pointerInsideKeepOpen: true), .error, [], nil),
            row("error", "contentChanged", .error, error, .contentChanged(editing, pointerInsideKeepOpen: true), .itemEditing, [], nil),
            row("error", "pointerChanged", .error, error, .pointerChanged(isInsideKeepOpen: false, at: 10), .error, [], nil),
            row("error", "exitDeadlineReached", .error, error, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .error, [], nil),
            row("error", "externalFocusLost", .error, error, .externalFocusLost(editSaveSucceeded: false), .error, [], nil),
            row("error", "pinToggled", .error, error, .pinToggled(pointerInsideKeepOpen: true), .pinned, [.setPinned(true)], nil),
            row("error", "didReturnToCorner", .error, error, .didReturnToCorner(pointerInsideKeepOpen: false), .error, [], nil),
            row("error", "closeRequested", .error, error, .closeRequested, .closing, [.dismiss], nil),
            row("error", "didBeginClosing", .error, error, .didBeginClosing, .closing, [], nil),
            row("error", "didClose", .error, error, .didClose, .hidden, [], nil),

            // closing
            row("closing", "presentRequested", .closing, closing, .presentRequested, .closing, [.reverseClosing], nil),
            row("closing", "didOpen", .closing, closing, .didOpen(content: draft, pointerInsideKeepOpen: true), .closing, [], nil),
            row("closing", "contentChanged", .closing, closing, .contentChanged(draft, pointerInsideKeepOpen: true), .draftLocked, [.reverseClosing], nil),
            row("closing", "pointerChanged", .closing, closing, .pointerChanged(isInsideKeepOpen: true, at: 10), .closing, [.reverseClosing], nil),
            row("closing", "exitDeadlineReached", .closing, closing, .exitDeadlineReached(PanelDeadline(generation: 1, dueAt: 10.120), isInsideKeepOpen: false, at: 10.120), .closing, [], nil),
            row("closing", "externalFocusLost", .closing, closing, .externalFocusLost(editSaveSucceeded: false), .closing, [], nil),
            row("closing", "pinToggled", .closing, closing, .pinToggled(pointerInsideKeepOpen: true), .closing, [], nil),
            row("closing", "didReturnToCorner", .closing, closing, .didReturnToCorner(pointerInsideKeepOpen: false), .closing, [], nil),
            row("closing", "closeRequested", .closing, closing, .closeRequested, .closing, [], nil),
            row("closing", "didBeginClosing", .closing, closing, .didBeginClosing, .closing, [], nil),
            row("closing", "didClose", .closing, closing, .didClose, .hidden, [], nil)
        ]
        let stateNames = [
            "hidden", "opening", "openEmpty", "draftLocked",
            "itemEditing", "pinned", "error", "closing"
        ]
        let eventCategories = [
            "presentRequested", "didOpen", "contentChanged", "pointerChanged",
            "exitDeadlineReached", "externalFocusLost", "pinToggled",
            "didReturnToCorner", "closeRequested", "didBeginClosing", "didClose"
        ]
        let expectedPairs = Set(stateNames.flatMap { stateName in
            eventCategories.map { "\(stateName)|\($0)" }
        })
        let actualPairs = Set(cases.map { "\($0.stateName)|\($0.eventCategory)" })

        XCTAssertEqual(cases.count, expectedPairs.count)
        XCTAssertEqual(actualPairs, expectedPairs)
        for testCase in cases {
            var machine = testCase.makeMachine()
            XCTAssertEqual(machine.state, testCase.initialState, "initial state for \(testCase.stateName)")
            XCTAssertEqual(machine.handle(testCase.event), testCase.expectedEffects)
            XCTAssertEqual(machine.state, testCase.expectedState)
            XCTAssertEqual(machine.nextDeadline, testCase.expectedDeadline)
        }
    }

    private func makeOpenMachine(content: PanelContentStatus) -> PanelStateMachine {
        var machine = PanelStateMachine()
        XCTAssertEqual(machine.handle(.presentRequested), [.present])
        XCTAssertEqual(
            machine.handle(.didOpen(content: content, pointerInsideKeepOpen: true)),
            []
        )
        return machine
    }
}

private extension Array where Element == PanelEffect {
    var scheduledDeadline: PanelDeadline? {
        compactMap { effect in
            guard case let .schedule(deadline) = effect else { return nil }
            return deadline
        }.first
    }
}

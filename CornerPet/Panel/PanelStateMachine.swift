import Foundation

enum PanelState: Equatable {
    case hidden
    case opening
    case openEmpty
    case draftLocked
    case itemEditing
    case pinned
    case error
    case closing
}

struct PanelContentStatus: Equatable {
    let hasDraft: Bool
    let hasItemEdit: Bool
    let hasError: Bool
}

struct PanelDeadline: Equatable {
    let generation: Int
    let dueAt: TimeInterval
}

enum PanelEvent: Equatable {
    case presentRequested
    case didOpen(content: PanelContentStatus, pointerInsideKeepOpen: Bool)
    case contentChanged(PanelContentStatus, pointerInsideKeepOpen: Bool)
    case pointerChanged(isInsideKeepOpen: Bool, at: TimeInterval)
    case exitDeadlineReached(PanelDeadline, isInsideKeepOpen: Bool, at: TimeInterval)
    case externalFocusLost(editSaveSucceeded: Bool?)
    case pinToggled(pointerInsideKeepOpen: Bool)
    case didReturnToCorner(pointerInsideKeepOpen: Bool)
    case closeRequested
    case didBeginClosing
    case didClose
}

enum PanelEffect: Equatable {
    case schedule(PanelDeadline)
    case cancelDeadline
    case present
    case dismiss
    case reverseClosing
    case setPinned(Bool)
    case returnToCorner

    // These aliases keep call sites expressive without introducing another
    // public state or a second lifecycle vocabulary.
    static var cancelExit: Self { .cancelDeadline }
    static var close: Self { .dismiss }

    static func scheduleExit(_ deadline: PanelDeadline) -> Self {
        .schedule(deadline)
    }
}

struct PanelStateMachine {
    static let emptyExitDuration: TimeInterval = 0.120

    private enum UnpinnedContent: Equatable {
        case openEmpty
        case draftLocked
        case itemEditing
    }

    private var content = PanelContentStatus(
        hasDraft: false,
        hasItemEdit: false,
        hasError: false
    )
    private var unpinnedContent: UnpinnedContent = .openEmpty
    private var isPinned = false
    private var awaitingCornerReturn = false
    private var reverseRequested = false
    private var nextGeneration = 0
    private var lastAcceptedTime: TimeInterval?

    private(set) var state: PanelState = .hidden
    private(set) var nextDeadline: PanelDeadline?

    var pendingDeadline: PanelDeadline? {
        nextDeadline
    }

    var contentStatus: PanelContentStatus {
        content
    }

    mutating func handle(_ event: PanelEvent) -> [PanelEffect] {
        switch event {
        case .presentRequested:
            return presentRequested()
        case let .didOpen(content, pointerInsideKeepOpen):
            return didOpen(content: content, pointerInsideKeepOpen: pointerInsideKeepOpen)
        case let .contentChanged(content, pointerInsideKeepOpen):
            return contentChanged(content: content, pointerInsideKeepOpen: pointerInsideKeepOpen)
        case let .pointerChanged(isInsideKeepOpen, at: time):
            return pointerChanged(isInsideKeepOpen: isInsideKeepOpen, at: time)
        case let .exitDeadlineReached(deadline, isInsideKeepOpen, at: time):
            return exitDeadlineReached(
                deadline,
                isInsideKeepOpen: isInsideKeepOpen,
                at: time
            )
        case let .externalFocusLost(editSaveSucceeded):
            return externalFocusLost(editSaveSucceeded: editSaveSucceeded)
        case let .pinToggled(pointerInsideKeepOpen):
            return pinToggled(pointerInsideKeepOpen: pointerInsideKeepOpen)
        case let .didReturnToCorner(pointerInsideKeepOpen):
            return didReturnToCorner(pointerInsideKeepOpen: pointerInsideKeepOpen)
        case .closeRequested:
            return closeRequested()
        case .didBeginClosing:
            return didBeginClosing()
        case .didClose:
            return didClose()
        }
    }

    private mutating func presentRequested() -> [PanelEffect] {
        switch state {
        case .hidden:
            isPinned = false
            awaitingCornerReturn = false
            reverseRequested = false
            state = .opening
            return [.present]
        case .closing where !reverseRequested:
            reverseRequested = true
            return [.reverseClosing]
        case .closing where reverseRequested:
            state = .opening
            return []
        case .opening, .openEmpty, .draftLocked, .itemEditing, .pinned, .error, .closing:
            return []
        }
    }

    private mutating func didOpen(
        content: PanelContentStatus,
        pointerInsideKeepOpen: Bool
    ) -> [PanelEffect] {
        guard state == .opening else {
            return []
        }

        self.content = content
        unpinnedContent = unpinnedContent(for: content)
        reverseRequested = false

        awaitingCornerReturn = false
        state = isPinned ? .pinned : visibleState
        _ = pointerInsideKeepOpen
        return []
    }

    private mutating func contentChanged(
        content: PanelContentStatus,
        pointerInsideKeepOpen: Bool
    ) -> [PanelEffect] {
        self.content = content
        unpinnedContent = unpinnedContent(for: content)

        guard state != .hidden else {
            return []
        }

        if isPinned {
            state = .pinned
            return cancelPendingDeadlineIfNeeded()
        }

        switch state {
        case .opening:
            return []
        case .closing:
            if content.hasError || content.hasDraft || content.hasItemEdit {
                state = visibleState
                reverseRequested = true
                return [.reverseClosing]
            }
            return []
        case .openEmpty, .draftLocked, .itemEditing, .error:
            state = visibleState
            _ = pointerInsideKeepOpen
            return cancelPendingDeadlineIfNeeded()
        case .hidden, .pinned:
            return []
        }
    }

    private mutating func pointerChanged(
        isInsideKeepOpen: Bool,
        at time: TimeInterval
    ) -> [PanelEffect] {
        guard accept(time: time) else {
            return []
        }

        switch state {
        case .openEmpty:
            if isInsideKeepOpen {
                return cancelPendingDeadlineIfNeeded()
            }
            return scheduleExitIfNeeded(at: time)
        case .closing where isInsideKeepOpen && !reverseRequested:
            reverseRequested = true
            return [.reverseClosing]
        case .hidden, .opening, .draftLocked, .itemEditing, .pinned, .error, .closing:
            return []
        }
    }

    private mutating func exitDeadlineReached(
        _ deadline: PanelDeadline,
        isInsideKeepOpen: Bool,
        at time: TimeInterval
    ) -> [PanelEffect] {
        guard nextDeadline == deadline,
              time.isFinite,
              lastAcceptedTime.map({ time >= $0 }) ?? true,
              time >= deadline.dueAt else {
            return []
        }

        lastAcceptedTime = time
        nextDeadline = nil

        guard state == .openEmpty else {
            return []
        }
        guard !isInsideKeepOpen else {
            return [.cancelDeadline]
        }

        state = .closing
        reverseRequested = false
        return [.dismiss]
    }

    private mutating func externalFocusLost(
        editSaveSucceeded: Bool?
    ) -> [PanelEffect] {
        switch state {
        case .hidden, .opening, .pinned, .error, .closing:
            return []
        case .openEmpty, .draftLocked:
            return beginDismissal()
        case .itemEditing:
            switch editSaveSucceeded {
            case .some(true):
                return beginDismissal()
            case .some(false):
                content = PanelContentStatus(
                    hasDraft: content.hasDraft,
                    hasItemEdit: true,
                    hasError: true
                )
                state = .error
                return []
            case .none:
                return []
            }
        }
    }

    private mutating func pinToggled(
        pointerInsideKeepOpen: Bool
    ) -> [PanelEffect] {
        guard state != .hidden,
              state != .opening,
              state != .closing else {
            return []
        }

        if isPinned {
            isPinned = false
            awaitingCornerReturn = true
            state = visibleState
            let effects = [PanelEffect.setPinned(false), .returnToCorner]
            _ = pointerInsideKeepOpen
            return effects
        }

        isPinned = true
        awaitingCornerReturn = false
        state = .pinned
        var effects = cancelPendingDeadlineIfNeeded()
        effects.append(.setPinned(true))
        _ = pointerInsideKeepOpen
        return effects
    }

    private mutating func didReturnToCorner(
        pointerInsideKeepOpen: Bool
    ) -> [PanelEffect] {
        guard awaitingCornerReturn else {
            return []
        }

        awaitingCornerReturn = false
        if state == .closing, reverseRequested {
            state = visibleState
            reverseRequested = false
            return []
        }

        guard state == .openEmpty, !pointerInsideKeepOpen else {
            return []
        }

        state = .closing
        reverseRequested = false
        return [.dismiss]
    }

    private mutating func closeRequested() -> [PanelEffect] {
        guard state != .hidden, state != .closing else {
            return []
        }
        return beginDismissal()
    }

    private mutating func didBeginClosing() -> [PanelEffect] {
        guard state != .hidden else {
            return []
        }
        let effects = cancelPendingDeadlineIfNeeded()
        state = .closing
        reverseRequested = false
        return effects
    }

    private mutating func didClose() -> [PanelEffect] {
        let effects: [PanelEffect] = nextDeadline == nil ? [] : [.cancelDeadline]
        state = .hidden
        isPinned = false
        awaitingCornerReturn = false
        reverseRequested = false
        nextDeadline = nil
        return effects
    }

    private mutating func beginDismissal() -> [PanelEffect] {
        var effects = cancelPendingDeadlineIfNeeded()
        state = .closing
        reverseRequested = false
        effects.append(.dismiss)
        return effects
    }

    private mutating func scheduleExitIfNeeded(at time: TimeInterval) -> [PanelEffect] {
        guard nextDeadline == nil,
              time.isFinite else {
            return []
        }

        let dueAt = time + Self.emptyExitDuration
        guard dueAt.isFinite, dueAt > time else {
            return []
        }

        nextGeneration += 1
        let deadline = PanelDeadline(generation: nextGeneration, dueAt: dueAt)
        nextDeadline = deadline
        return [.schedule(deadline)]
    }

    private mutating func cancelPendingDeadlineIfNeeded() -> [PanelEffect] {
        guard nextDeadline != nil else {
            return []
        }
        nextDeadline = nil
        return [.cancelDeadline]
    }

    private mutating func accept(time: TimeInterval) -> Bool {
        guard time.isFinite,
              lastAcceptedTime.map({ time >= $0 }) ?? true else {
            return false
        }
        lastAcceptedTime = time
        return true
    }

    private var visibleState: PanelState {
        guard !isPinned else { return .pinned }
        if content.hasError {
            return .error
        }
        switch unpinnedContent {
        case .openEmpty:
            return .openEmpty
        case .draftLocked:
            return .draftLocked
        case .itemEditing:
            return .itemEditing
        }
    }

    private func unpinnedContent(for content: PanelContentStatus) -> UnpinnedContent {
        if content.hasItemEdit {
            return .itemEditing
        }
        if content.hasDraft {
            return .draftLocked
        }
        return .openEmpty
    }
}

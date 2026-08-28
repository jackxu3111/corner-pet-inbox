import Foundation

struct HotCornerPointerPresence: Equatable {
    let isInsideTrigger: Bool
    let isInsidePanel: Bool

    var isInsideKeepOpen: Bool {
        isInsideTrigger || isInsidePanel
    }
}

struct HotCornerDeadline: Equatable {
    let kind: Kind
    let generation: Int
    let dueAt: TimeInterval

    enum Kind: Equatable {
        case dwell
    }

    init(kind: Kind = .dwell, generation: Int, dueAt: TimeInterval) {
        self.kind = kind
        self.generation = generation
        self.dueAt = dueAt
    }
}

enum HotCornerEvent: Equatable {
    case presenceChanged(HotCornerPointerPresence, at: TimeInterval)
    case deadlineReached(HotCornerDeadline, presence: HotCornerPointerPresence, at: TimeInterval)
    case panelBeganOpening(at: TimeInterval)
    case panelDidOpen(at: TimeInterval)
    case panelBeganClosing(at: TimeInterval)
    case panelDidClose(at: TimeInterval)
    case escapePressed(at: TimeInterval)
}

enum HotCornerEffect: Equatable {
    case schedule(HotCornerDeadline)
    case cancelDeadline
    case present
    case reverseClosing
}

enum HotCornerState: Equatable {
    case idle
    case dwelling(startedAt: TimeInterval, deadline: HotCornerDeadline)
    case opening
    case open
    case closing(reverseRequested: Bool)
    case suppressedUntilTriggerExit
}

struct HotCornerStateMachine {
    private let dwellDuration: TimeInterval
    private var nextGeneration = 0
    private var lastAcceptedTime: TimeInterval?
    private var lastPresence = HotCornerPointerPresence(
        isInsideTrigger: false,
        isInsidePanel: false
    )

    private(set) var state: HotCornerState = .idle
    private(set) var nextDeadline: HotCornerDeadline?

    init(dwellDuration: TimeInterval = DwellTiming.duration) {
        self.dwellDuration = dwellDuration
    }

    mutating func handle(_ event: HotCornerEvent) -> [HotCornerEffect] {
        switch event {
        case let .presenceChanged(presence, at: time):
            return handlePresenceChanged(presence, at: time)
        case let .deadlineReached(deadline, presence, at: time):
            return handleDeadlineReached(deadline, presence: presence, at: time)
        case let .panelBeganOpening(at: time):
            return handlePanelBeganOpening(at: time)
        case let .panelDidOpen(at: time):
            return handlePanelDidOpen(at: time)
        case let .panelBeganClosing(at: time):
            return handlePanelBeganClosing(at: time)
        case let .panelDidClose(at: time):
            return handlePanelDidClose(at: time)
        case let .escapePressed(at: time):
            _ = accept(time: time)
            return []
        }
    }

    private mutating func handlePresenceChanged(
        _ presence: HotCornerPointerPresence,
        at time: TimeInterval
    ) -> [HotCornerEffect] {
        guard accept(time: time) else {
            return []
        }

        lastPresence = presence
        switch state {
        case .idle:
            guard presence.isInsideTrigger else { return [] }
            guard let deadline = makeDwellDeadline(at: time) else { return [] }
            state = .dwelling(startedAt: time, deadline: deadline)
            nextDeadline = deadline
            return [.schedule(deadline)]
        case .dwelling:
            guard !presence.isInsideTrigger else { return [] }
            state = .idle
            nextDeadline = nil
            return [.cancelDeadline]
        case .closing where presence.isInsideTrigger:
            guard case let .closing(reverseRequested) = state, !reverseRequested else {
                return []
            }
            state = .closing(reverseRequested: true)
            return [.reverseClosing]
        case .suppressedUntilTriggerExit:
            guard !presence.isInsideTrigger else { return [] }
            state = .idle
            return []
        case .opening, .open, .closing:
            return []
        }
    }

    private mutating func handleDeadlineReached(
        _ deadline: HotCornerDeadline,
        presence: HotCornerPointerPresence,
        at time: TimeInterval
    ) -> [HotCornerEffect] {
        guard nextDeadline == deadline,
              deadline.kind == .dwell,
              time.isFinite,
              lastAcceptedTime.map({ time >= $0 }) ?? true,
              time >= deadline.dueAt else {
            return []
        }

        lastAcceptedTime = time
        nextDeadline = nil
        guard case let .dwelling(_, currentDeadline) = state,
              currentDeadline == deadline else {
            return []
        }

        lastPresence = presence
        guard presence.isInsideTrigger else {
            state = .idle
            return [.cancelDeadline]
        }
        state = .opening
        return [.present]
    }

    private mutating func handlePanelDidOpen(at time: TimeInterval) -> [HotCornerEffect] {
        guard accept(time: time) else { return [] }
        if case .opening = state {
            state = .open
        }
        return []
    }

    private mutating func handlePanelBeganOpening(at time: TimeInterval) -> [HotCornerEffect] {
        guard accept(time: time) else { return [] }
        if case .dwelling = state {
            nextDeadline = nil
            state = .opening
            return [.cancelDeadline]
        }
        if case .closing(reverseRequested: true) = state {
            state = .opening
        }
        return []
    }

    private mutating func handlePanelBeganClosing(at time: TimeInterval) -> [HotCornerEffect] {
        guard accept(time: time) else { return [] }
        switch state {
        case .opening, .open:
            nextDeadline = nil
            state = .closing(reverseRequested: false)
        case .closing, .idle, .dwelling, .suppressedUntilTriggerExit:
            break
        }
        return []
    }

    private mutating func handlePanelDidClose(at time: TimeInterval) -> [HotCornerEffect] {
        guard accept(time: time) else { return [] }
        guard case .closing = state else { return [] }
        nextDeadline = nil
        state = lastPresence.isInsideTrigger
            ? .suppressedUntilTriggerExit
            : .idle
        return []
    }

    private mutating func makeDwellDeadline(at time: TimeInterval) -> HotCornerDeadline? {
        guard time.isFinite,
              dwellDuration.isFinite,
              dwellDuration > 0 else {
            return nil
        }
        let dueAt = time + dwellDuration
        guard dueAt.isFinite, dueAt > time else { return nil }
        nextGeneration += 1
        return HotCornerDeadline(generation: nextGeneration, dueAt: dueAt)
    }

    private mutating func accept(time: TimeInterval) -> Bool {
        guard time.isFinite,
              lastAcceptedTime.map({ time >= $0 }) ?? true else {
            return false
        }
        lastAcceptedTime = time
        return true
    }
}

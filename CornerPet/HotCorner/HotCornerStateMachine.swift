import CoreGraphics
import Foundation

struct HotCornerTarget: Equatable {
    let screenID: UInt32
    let corner: TriggerCorner
    let regions: [CGRect]
}

enum HotCornerAction: Equatable {
    case none
    case present(screenID: UInt32)
    case reverseClosing(screenID: UInt32)
}

enum HotCornerEvent {
    case pointerObserved(location: CGPoint, at: TimeInterval, targets: [HotCornerTarget])
    case panelBeganOpening(screenID: UInt32, at: TimeInterval)
    case panelDidOpen(screenID: UInt32, at: TimeInterval)
    case panelBeganClosing(screenID: UInt32, at: TimeInterval)
    case panelDidClose(at: TimeInterval)
}

enum HotCornerState: Equatable {
    case idle
    case dwelling(target: HotCornerTarget, enteredAt: TimeInterval)
    case presentRequested(screenID: UInt32)
    case opening(screenID: UInt32)
    case open(screenID: UInt32)
    case closing(screenID: UInt32, reverseRequested: Bool)
    case postCloseDebounce(until: TimeInterval)
}

struct HotCornerStateMachine {
    private let dwellDuration: TimeInterval
    private var lastObservedTime: TimeInterval?

    private(set) var state: HotCornerState = .idle
    private(set) var nextEvaluationDeadline: TimeInterval?

    init(dwellPreset: DwellPreset = .standard) {
        dwellDuration = dwellPreset.rawValue
    }

    mutating func handle(_ event: HotCornerEvent) -> HotCornerAction {
        switch event {
        case let .pointerObserved(location, at, targets):
            handlePointerObserved(location: location, at: at, targets: targets)
        case let .panelBeganOpening(screenID, at):
            handlePanelBeganOpening(screenID: screenID, at: at)
        case let .panelDidOpen(screenID, at):
            handlePanelDidOpen(screenID: screenID, at: at)
        case let .panelBeganClosing(screenID, at):
            handlePanelBeganClosing(screenID: screenID, at: at)
        case let .panelDidClose(at):
            handlePanelDidClose(at: at)
        }
    }

    private mutating func handlePointerObserved(
        location: CGPoint,
        at time: TimeInterval,
        targets: [HotCornerTarget]
    ) -> HotCornerAction {
        guard accept(time: time) else {
            if case .dwelling = state {
                state = .idle
                nextEvaluationDeadline = nil
            }
            return .none
        }

        let target: HotCornerTarget?
        if case let .dwelling(currentTarget, _) = state,
           targets.contains(currentTarget),
           contains(location: location, in: currentTarget.regions) {
            target = currentTarget
        } else {
            target = targets.first { target in
                contains(location: location, in: target.regions)
            }
        }

        switch state {
        case .idle:
            guard let target else {
                return .none
            }
            guard let deadline = finiteDeadline(from: time, adding: dwellDuration) else {
                invalidateTiming()
                return .none
            }

            state = .dwelling(target: target, enteredAt: time)
            nextEvaluationDeadline = deadline
            return .none

        case let .dwelling(currentTarget, enteredAt):
            guard let target else {
                state = .idle
                nextEvaluationDeadline = nil
                return .none
            }

            guard target == currentTarget else {
                guard let deadline = finiteDeadline(from: time, adding: dwellDuration) else {
                    invalidateTiming()
                    return .none
                }
                state = .dwelling(target: target, enteredAt: time)
                nextEvaluationDeadline = deadline
                return .none
            }

            guard let deadline = finiteDeadline(from: enteredAt, adding: dwellDuration) else {
                invalidateTiming()
                return .none
            }
            guard time >= deadline else {
                return .none
            }

            state = .presentRequested(screenID: target.screenID)
            nextEvaluationDeadline = nil
            return .present(screenID: target.screenID)

        case .presentRequested, .opening, .open:
            return .none

        case let .postCloseDebounce(until):
            guard time >= until else {
                return .none
            }

            guard let target else {
                state = .idle
                nextEvaluationDeadline = nil
                return .none
            }
            guard let deadline = finiteDeadline(from: time, adding: dwellDuration) else {
                invalidateTiming()
                return .none
            }

            state = .dwelling(target: target, enteredAt: time)
            nextEvaluationDeadline = deadline
            return .none

        case let .closing(screenID, reverseRequested):
            guard !reverseRequested,
                  targets.contains(where: { target in
                      target.screenID == screenID && contains(location: location, in: target.regions)
                  }) else {
                return .none
            }

            state = .closing(screenID: screenID, reverseRequested: true)
            return .reverseClosing(screenID: screenID)
        }
    }

    private mutating func handlePanelBeganOpening(screenID: UInt32, at time: TimeInterval) -> HotCornerAction {
        guard accept(time: time) else {
            invalidateDwellIfNeeded()
            return .none
        }

        switch state {
        case let .presentRequested(requestedScreenID) where requestedScreenID == screenID:
            state = .opening(screenID: screenID)
            nextEvaluationDeadline = nil
        case let .closing(closingScreenID, reverseRequested)
            where closingScreenID == screenID && reverseRequested:
            state = .opening(screenID: screenID)
            nextEvaluationDeadline = nil
        default:
            break
        }

        return .none
    }

    private mutating func handlePanelDidOpen(screenID: UInt32, at time: TimeInterval) -> HotCornerAction {
        guard accept(time: time) else {
            invalidateDwellIfNeeded()
            return .none
        }

        if case let .opening(openingScreenID) = state, openingScreenID == screenID {
            state = .open(screenID: screenID)
            nextEvaluationDeadline = nil
        }

        return .none
    }

    private mutating func handlePanelBeganClosing(screenID: UInt32, at time: TimeInterval) -> HotCornerAction {
        guard accept(time: time) else {
            invalidateDwellIfNeeded()
            return .none
        }

        if case let .open(openScreenID) = state, openScreenID == screenID {
            state = .closing(screenID: screenID, reverseRequested: false)
            nextEvaluationDeadline = nil
        }

        return .none
    }

    private mutating func handlePanelDidClose(at time: TimeInterval) -> HotCornerAction {
        guard accept(time: time) else {
            invalidateDwellIfNeeded()
            return .none
        }
        guard case .closing(_, reverseRequested: false) = state else {
            return .none
        }

        guard let deadline = finiteDeadline(from: time, adding: 0.080) else {
            invalidateTiming()
            return .none
        }
        state = .postCloseDebounce(until: deadline)
        nextEvaluationDeadline = deadline
        return .none
    }

    private mutating func accept(time: TimeInterval) -> Bool {
        guard time.isFinite else {
            return false
        }
        guard lastObservedTime.map({ time >= $0 }) ?? true else {
            return false
        }

        lastObservedTime = time
        return true
    }

    private mutating func invalidateDwellIfNeeded() {
        if case .dwelling = state {
            state = .idle
            nextEvaluationDeadline = nil
        }
    }

    private mutating func invalidateTiming() {
        state = .idle
        nextEvaluationDeadline = nil
        lastObservedTime = nil
    }

    private func finiteDeadline(from time: TimeInterval, adding duration: TimeInterval) -> TimeInterval? {
        let deadline = time + duration
        guard deadline.isFinite, deadline > time else {
            return nil
        }
        return deadline
    }

    private func contains(location: CGPoint, in regions: [CGRect]) -> Bool {
        regions.contains { region in
            location.x >= region.minX && location.x <= region.maxX
                && location.y >= region.minY && location.y <= region.maxY
        }
    }
}

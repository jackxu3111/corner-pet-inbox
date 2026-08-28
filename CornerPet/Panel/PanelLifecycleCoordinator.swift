import Foundation
import Observation

@MainActor
@Observable
final class PanelLifecycleCoordinator {
    private struct PendingDeadline {
        let deadline: PanelDeadline
        let cancellation: HotCornerCancellation
    }

    private weak var panelController: CapturePanelController?
    private let clock: @MainActor () -> TimeInterval
    private let pointerInsideKeepOpen: @MainActor () -> Bool
    private let scheduler: PanelDeadlineScheduling
    private let presentPanel: (UInt32) -> Void
    private let dismissPanel: () -> Void
    private let reverseClosingPanel: (UInt32) -> Void
    private let setPinnedPanel: (Bool) -> Void
    private let returnToCornerPanel: () -> Void

    private var stateMachine = PanelStateMachine()
    private var pendingDeadline: PendingDeadline?
    private var requestedScreenID: UInt32?
    private var isInsideTrigger = false
    private var schedulingEventTime: TimeInterval?

    private(set) var state: PanelState = .hidden
    private(set) var nextDeadline: PanelDeadline?

    var contentStatus: PanelContentStatus {
        stateMachine.contentStatus
    }

    var isPinned: Bool {
        state == .pinned
    }

    var onStateChanged: (() -> Void)?

    init(
        panelController: CapturePanelController? = nil,
        scheduler: PanelDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pointerInsideKeepOpen: @escaping @MainActor () -> Bool = { false },
        presentPanel: @escaping (UInt32) -> Void = { _ in },
        dismissPanel: @escaping () -> Void = {},
        reverseClosingPanel: @escaping (UInt32) -> Void = { _ in },
        setPinnedPanel: @escaping (Bool) -> Void = { _ in },
        returnToCornerPanel: @escaping () -> Void = {}
    ) {
        self.panelController = panelController
        self.scheduler = scheduler
        self.clock = clock
        self.pointerInsideKeepOpen = pointerInsideKeepOpen
        self.presentPanel = presentPanel
        self.dismissPanel = dismissPanel
        self.reverseClosingPanel = reverseClosingPanel
        self.setPinnedPanel = setPinnedPanel
        self.returnToCornerPanel = returnToCornerPanel
    }

    func presentRequested(screenID: UInt32) {
        requestedScreenID = screenID
        handle(.presentRequested)
    }

    func didOpen(
        content: PanelContentStatus,
        pointerInsideKeepOpen: Bool
    ) {
        handle(.didOpen(
            content: content,
            pointerInsideKeepOpen: pointerInsideKeepOpen || isInsideTrigger
        ))
    }

    func contentChanged(
        _ content: PanelContentStatus,
        pointerInsideKeepOpen: Bool
    ) {
        let isInside = pointerInsideKeepOpen || isInsideTrigger
        handle(.contentChanged(content, pointerInsideKeepOpen: isInside))
        guard state != .hidden else { return }
        pointerChanged(isInsideKeepOpen: isInside, at: clock())
    }

    func pointerChanged(isInsideKeepOpen: Bool, at time: TimeInterval) {
        withSchedulingTime(time) {
            handle(.pointerChanged(
                isInsideKeepOpen: isInsideKeepOpen || isInsideTrigger,
                at: time
            ))
        }
    }

    func refreshPresence() {
        let now = clock()
        pointerChanged(isInsideKeepOpen: pointerInsideKeepOpen(), at: now)
    }

    func setTriggerPresence(_ isInside: Bool, at time: TimeInterval? = nil) {
        isInsideTrigger = isInside
        let eventTime = time ?? clock()
        withSchedulingTime(eventTime) {
            handle(.pointerChanged(
                isInsideKeepOpen: isInside || pointerInsideKeepOpen(),
                at: eventTime
            ))
        }
    }

    func externalFocusLost(editSaveSucceeded: Bool?) {
        handle(.externalFocusLost(editSaveSucceeded: editSaveSucceeded))
    }

    func pinToggled(pointerInsideKeepOpen: Bool) {
        handle(.pinToggled(
            pointerInsideKeepOpen: pointerInsideKeepOpen || isInsideTrigger
        ))
    }

    func didReturnToCorner(pointerInsideKeepOpen: Bool) {
        let isInside = pointerInsideKeepOpen
            || isInsideTrigger
            || self.pointerInsideKeepOpen()
        handle(.didReturnToCorner(pointerInsideKeepOpen: isInside))
    }

    func closeRequested() {
        handle(.closeRequested)
    }

    func didBeginOpening(screenID: UInt32? = nil) {
        if let screenID {
            requestedScreenID = screenID
        }
    }

    func didBeginClosing() {
        handle(.didBeginClosing)
    }

    func didClose() {
        handle(.didClose)
    }

    func reverseClosing(screenID: UInt32? = nil) {
        if let screenID {
            requestedScreenID = screenID
        }
        handle(.pointerChanged(isInsideKeepOpen: true, at: clock()))
    }

    func stop() {
        pendingDeadline?.cancellation.cancel()
        pendingDeadline = nil
        nextDeadline = nil
        _ = stateMachine.handle(.didClose)
        state = .hidden
        isInsideTrigger = false
        onStateChanged?()
    }

    private func handle(_ event: PanelEvent) {
        let effects = stateMachine.handle(event)
        state = stateMachine.state
        nextDeadline = stateMachine.nextDeadline
        for effect in effects {
            apply(effect)
        }
        state = stateMachine.state
        nextDeadline = stateMachine.nextDeadline
        onStateChanged?()
    }

    private func apply(_ effect: PanelEffect) {
        switch effect {
        case let .schedule(deadline):
            schedule(deadline)
        case .cancelDeadline:
            pendingDeadline?.cancellation.cancel()
            pendingDeadline = nil
            nextDeadline = stateMachine.nextDeadline
        case .present:
            guard let screenID = requestedScreenID else { return }
            if let panelController {
                panelController.present(screenID: screenID)
            } else {
                presentPanel(screenID)
            }
        case .dismiss:
            if let panelController {
                panelController.dismiss()
            } else {
                dismissPanel()
            }
        case .reverseClosing:
            if let panelController {
                panelController.reverseClosing()
            } else if let screenID = requestedScreenID {
                reverseClosingPanel(screenID)
            }
        case let .setPinned(isPinned):
            if let panelController {
                panelController.setPinned(isPinned)
            } else {
                setPinnedPanel(isPinned)
            }
        case .returnToCorner:
            if let panelController {
                panelController.returnToCorner()
            } else {
                returnToCornerPanel()
            }
        }
    }

    private func schedule(_ deadline: PanelDeadline) {
        pendingDeadline?.cancellation.cancel()
        pendingDeadline = nil

        let clockNow = clock()
        guard clockNow.isFinite else { return }
        let eventTime = schedulingEventTime ?? clockNow
        guard eventTime.isFinite else { return }
        let referenceTime = max(clockNow, eventTime)
        let delay = max(0, deadline.dueAt - referenceTime)
        guard referenceTime.isFinite, delay.isFinite else { return }

        let cancellation = scheduler.schedule(after: delay) { [weak self] in
            self?.fire(deadline)
        }
        pendingDeadline = PendingDeadline(deadline: deadline, cancellation: cancellation)
    }

    private func withSchedulingTime(
        _ time: TimeInterval,
        _ operation: () -> Void
    ) {
        let previous = schedulingEventTime
        schedulingEventTime = time
        operation()
        schedulingEventTime = previous
    }

    private func fire(_ deadline: PanelDeadline) {
        guard pendingDeadline?.deadline == deadline else { return }

        pendingDeadline = nil
        let now = clock()
        guard now.isFinite else { return }
        guard now >= deadline.dueAt else {
            schedule(deadline)
            return
        }

        let isInside = isInsideTrigger || pointerInsideKeepOpen()
        handle(.exitDeadlineReached(
            deadline,
            isInsideKeepOpen: isInside,
            at: now
        ))
    }
}

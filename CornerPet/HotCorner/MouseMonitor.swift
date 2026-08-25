import AppKit
import Foundation

@MainActor
final class MouseMonitor {
    private let dwellPreset: DwellPreset
    private let clock: () -> TimeInterval
    private let targetsProvider: () -> [HotCornerTarget]
    private let actionHandler: (HotCornerAction) -> Void

    private var stateMachine: HotCornerStateMachine
    private var localMonitorToken: Any?
    private var globalMonitorToken: Any?
    private var deadlineTask: Task<Void, Never>?
    private var scheduledDeadline: TimeInterval?
    private var lastEventNumber: Int?

    private(set) var isRunning = false

    init(
        dwellPreset: DwellPreset = DwellPreset.default,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        targetsProvider: @escaping () -> [HotCornerTarget],
        actionHandler: @escaping (HotCornerAction) -> Void
    ) {
        self.dwellPreset = dwellPreset
        self.clock = clock
        self.targetsProvider = targetsProvider
        self.actionHandler = actionHandler
        stateMachine = HotCornerStateMachine(dwellPreset: dwellPreset)
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else {
            return true
        }

        guard let localMonitorToken = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.enqueue(eventNumber: event.eventNumber)
            return event
        }) else {
            return false
        }

        guard let globalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            self?.enqueue(eventNumber: event.eventNumber)
        }) else {
            NSEvent.removeMonitor(localMonitorToken)
            return false
        }

        self.localMonitorToken = localMonitorToken
        self.globalMonitorToken = globalMonitorToken
        isRunning = true
        scheduleDeadlineIfNeeded()
        return true
    }

    func stop() {
        guard isRunning || localMonitorToken != nil || globalMonitorToken != nil else {
            return
        }

        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadline = nil

        if let localMonitorToken {
            NSEvent.removeMonitor(localMonitorToken)
            self.localMonitorToken = nil
        }
        if let globalMonitorToken {
            NSEvent.removeMonitor(globalMonitorToken)
            self.globalMonitorToken = nil
        }

        lastEventNumber = nil
        stateMachine = HotCornerStateMachine(dwellPreset: dwellPreset)
        isRunning = false
    }

    func panelBeganOpening(screenID: UInt32) {
        handle(.panelBeganOpening(screenID: screenID, at: clock()))
    }

    func panelDidOpen(screenID: UInt32) {
        handle(.panelDidOpen(screenID: screenID, at: clock()))
    }

    func panelBeganClosing(screenID: UInt32) {
        handle(.panelBeganClosing(screenID: screenID, at: clock()))
    }

    func panelDidClose() {
        handle(.panelDidClose(at: clock()))
    }

    private nonisolated func enqueue(eventNumber: Int) {
        Task { @MainActor [weak self] in
            self?.consume(eventNumber: eventNumber)
        }
    }

    private func consume(eventNumber: Int) {
        guard isRunning else {
            return
        }
        guard lastEventNumber != eventNumber else {
            return
        }

        lastEventNumber = eventNumber
        handle(.pointerObserved(
            location: NSEvent.mouseLocation,
            at: clock(),
            targets: targetsProvider()
        ))
    }

    private func handle(_ event: HotCornerEvent) {
        let action = stateMachine.handle(event)
        if action != .none {
            actionHandler(action)
        }
        scheduleDeadlineIfNeeded()
    }

    private func scheduleDeadlineIfNeeded() {
        guard isRunning, let deadline = stateMachine.nextEvaluationDeadline else {
            deadlineTask?.cancel()
            deadlineTask = nil
            scheduledDeadline = nil
            return
        }

        guard scheduledDeadline != deadline else {
            return
        }

        deadlineTask?.cancel()
        scheduledDeadline = deadline

        let now = clock()
        guard now.isFinite else {
            scheduledDeadline = nil
            deadlineTask = nil
            return
        }

        let delay = max(0, deadline - now)
        guard delay.isFinite else {
            scheduledDeadline = nil
            deadlineTask = nil
            return
        }

        deadlineTask = Task { @MainActor [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }
            self?.evaluate(deadline: deadline)
        }
    }

    private func evaluate(deadline: TimeInterval) {
        guard isRunning,
              scheduledDeadline == deadline,
              stateMachine.nextEvaluationDeadline == deadline else {
            return
        }

        let now = clock()
        guard now.isFinite, now >= deadline else {
            deadlineTask = nil
            scheduledDeadline = nil
            scheduleDeadlineIfNeeded()
            return
        }

        deadlineTask = nil
        scheduledDeadline = nil
        handle(.pointerObserved(
            location: NSEvent.mouseLocation,
            at: now,
            targets: targetsProvider()
        ))
    }
}

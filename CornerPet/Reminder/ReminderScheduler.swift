import AppKit
import Foundation

enum ReminderEvaluationReason: Equatable, Sendable {
    case launch
    case minute
    case wake
    case calendarChanged
    case clockChanged
    case timeZoneChanged
    case settingsChanged
}

enum ReminderPresentation: Equatable, Sendable {
    case normal
    case snoozed
}

@MainActor
final class ReminderScheduler {
    private let stateStore: any ReminderStateStoring
    private let clock: @MainActor () -> Date
    private let calendarProvider: @MainActor () -> Calendar
    private let timerScheduler: HotCornerDeadlineScheduling
    private let defaultNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let wakeNotification: Notification.Name
    private let isCaptureVisible: @MainActor () -> Bool
    private let isReminderVisible: @MainActor () -> Bool
    private let onPresent: @MainActor (ReminderPresentation) -> Void

    private var configuration: ReminderConfiguration?
    private var minuteCancellation: (any HotCornerCancellation)?
    private var defaultObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private(set) var isRunning = false
    private(set) var lastEvaluationReason: ReminderEvaluationReason?

    init(
        stateStore: any ReminderStateStoring = ReminderStateStore(),
        clock: @escaping @MainActor () -> Date = { .now },
        calendarProvider: @escaping @MainActor () -> Calendar = { .autoupdatingCurrent },
        timerScheduler: HotCornerDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        defaultNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        wakeNotification: Notification.Name = NSWorkspace.didWakeNotification,
        isCaptureVisible: @escaping @MainActor () -> Bool,
        isReminderVisible: @escaping @MainActor () -> Bool,
        onPresent: @escaping @MainActor (ReminderPresentation) -> Void
    ) {
        self.stateStore = stateStore
        self.clock = clock
        self.calendarProvider = calendarProvider
        self.timerScheduler = timerScheduler
        self.defaultNotificationCenter = defaultNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.wakeNotification = wakeNotification
        self.isCaptureVisible = isCaptureVisible
        self.isReminderVisible = isReminderVisible
        self.onPresent = onPresent
    }

    func start(configuration: ReminderConfiguration) {
        guard !isRunning else {
            update(configuration: configuration)
            return
        }
        self.configuration = configuration
        isRunning = true
        registerObservers()
        scheduleMinuteIfNeeded()
        evaluate(reason: .launch)
    }

    func update(configuration: ReminderConfiguration) {
        guard isRunning else {
            start(configuration: configuration)
            return
        }
        self.configuration = configuration
        if configuration.isEnabled {
            scheduleMinuteIfNeeded()
        } else {
            cancelMinuteEvaluation()
        }
        evaluate(reason: .settingsChanged)
    }

    func evaluate(reason: ReminderEvaluationReason) {
        guard isRunning, let configuration else { return }
        lastEvaluationReason = reason
        let decision = ReminderPolicy.evaluate(ReminderPolicyInput(
            now: clock(),
            configuration: configuration,
            state: stateStore.load(),
            calendar: calendarProvider(),
            isCaptureVisible: isCaptureVisible(),
            isReminderVisible: isReminderVisible()
        ))
        apply(decision)
    }

    func snooze() {
        guard isRunning, configuration?.isEnabled == true else { return }
        stateStore.saveSnoozedUntil(clock().addingTimeInterval(600))
    }

    func completeCurrentReminder() {
        stateStore.saveSnoozedUntil(nil)
    }

    func stop() {
        guard isRunning else { return }
        cancelMinuteEvaluation()
        defaultObservers.forEach(defaultNotificationCenter.removeObserver)
        workspaceObservers.forEach(workspaceNotificationCenter.removeObserver)
        defaultObservers.removeAll()
        workspaceObservers.removeAll()
        configuration = nil
        isRunning = false
    }

    private func apply(_ decision: ReminderDecision) {
        switch decision {
        case .none:
            break
        case .clearSnooze, .consumeSnoozeWithoutPresentation:
            stateStore.saveSnoozedUntil(nil)
        case let .handleNormalWithoutPresentation(firedAt):
            stateStore.saveLastFiredAt(firedAt)
        case let .presentNormal(firedAt):
            stateStore.saveLastFiredAt(firedAt)
            onPresent(.normal)
        case .presentSnoozed:
            stateStore.saveSnoozedUntil(nil)
            onPresent(.snoozed)
        }
    }

    private func scheduleMinuteIfNeeded() {
        guard configuration?.isEnabled == true,
              minuteCancellation == nil else {
            return
        }
        minuteCancellation = timerScheduler.schedule(after: 60) { [weak self] in
            guard let self, isRunning else { return }
            minuteCancellation = nil
            evaluate(reason: .minute)
            scheduleMinuteIfNeeded()
        }
    }

    private func cancelMinuteEvaluation() {
        minuteCancellation?.cancel()
        minuteCancellation = nil
    }

    private func registerObservers() {
        workspaceObservers.append(workspaceNotificationCenter.addObserver(
            forName: wakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate(reason: .wake)
            }
        })

        observeDefault(.NSCalendarDayChanged, reason: .calendarChanged)
        observeDefault(.NSSystemClockDidChange, reason: .clockChanged)
        observeDefault(.NSSystemTimeZoneDidChange, reason: .timeZoneChanged)
    }

    private func observeDefault(
        _ name: Notification.Name,
        reason: ReminderEvaluationReason
    ) {
        defaultObservers.append(defaultNotificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate(reason: reason)
            }
        })
    }
}

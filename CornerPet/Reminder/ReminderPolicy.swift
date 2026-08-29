import Foundation

struct ReminderPolicyInput: Sendable {
    let now: Date
    let configuration: ReminderConfiguration
    let state: ReminderState
    let calendar: Calendar
    let isCaptureVisible: Bool
    let isReminderVisible: Bool
}

enum ReminderDecision: Equatable, Sendable {
    case none
    case clearSnooze
    case handleNormalWithoutPresentation(firedAt: Date)
    case consumeSnoozeWithoutPresentation
    case presentNormal(firedAt: Date)
    case presentSnoozed
}

enum ReminderPolicy {
    static func evaluate(_ input: ReminderPolicyInput) -> ReminderDecision {
        guard input.configuration.isEnabled else {
            return input.state.snoozedUntil == nil ? .none : .clearSnooze
        }
        guard !input.isReminderVisible else { return .none }

        if let snoozedUntil = input.state.snoozedUntil {
            guard input.now >= snoozedUntil else { return .none }
            return input.isCaptureVisible
                ? .consumeSnoozeWithoutPresentation
                : .presentSnoozed
        }

        if let lastFiredAt = input.state.lastFiredAt,
           input.calendar.isDate(lastFiredAt, inSameDayAs: input.now) {
            return .none
        }

        guard let scheduledDate = scheduledDate(
            on: input.now,
            dailyMinutes: input.configuration.dailyMinutes,
            calendar: input.calendar
        ), input.now >= scheduledDate else {
            return .none
        }

        return input.isCaptureVisible
            ? .handleNormalWithoutPresentation(firedAt: input.now)
            : .presentNormal(firedAt: input.now)
    }

    static func scheduledDate(
        on date: Date,
        dailyMinutes: Int,
        calendar: Calendar
    ) -> Date? {
        guard (0 ..< 24 * 60).contains(dailyMinutes) else { return nil }
        return calendar.date(
            bySettingHour: dailyMinutes / 60,
            minute: dailyMinutes % 60,
            second: 0,
            of: calendar.startOfDay(for: date),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

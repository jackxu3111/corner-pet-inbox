import Foundation

struct ReminderConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let dailyMinutes: Int
}

struct ReminderState: Equatable, Sendable {
    let lastFiredAt: Date?
    let snoozedUntil: Date?
}

@MainActor
protocol ReminderStateStoring {
    func load() -> ReminderState
    func saveLastFiredAt(_ date: Date?)
    func saveSnoozedUntil(_ date: Date?)
}

@MainActor
struct ReminderStateStore: ReminderStateStoring {
    private enum StorageKey {
        static let lastFiredAt = "CornerPet.reminder.lastFiredAt"
        static let snoozedUntil = "CornerPet.reminder.snoozedUntil"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ReminderState {
        ReminderState(
            lastFiredAt: defaults.object(forKey: StorageKey.lastFiredAt) as? Date,
            snoozedUntil: defaults.object(forKey: StorageKey.snoozedUntil) as? Date
        )
    }

    func saveLastFiredAt(_ date: Date?) {
        defaults.set(date, forKey: StorageKey.lastFiredAt)
    }

    func saveSnoozedUntil(_ date: Date?) {
        defaults.set(date, forKey: StorageKey.snoozedUntil)
    }
}

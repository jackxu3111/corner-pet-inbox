import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class ReminderStateStoreTests: XCTestCase {
    func testFreshStoreHasNoReminderHistory() {
        let store = ReminderStateStore(defaults: isolatedDefaults())

        XCTAssertEqual(
            store.load(),
            ReminderState(lastFiredAt: nil, snoozedUntil: nil)
        )
    }

    func testDatesRoundTripAndSnoozeCanBeCleared() {
        let defaults = isolatedDefaults()
        let store = ReminderStateStore(defaults: defaults)
        let firedAt = Date(timeIntervalSince1970: 100)
        let snoozedUntil = Date(timeIntervalSince1970: 700)

        store.saveLastFiredAt(firedAt)
        store.saveSnoozedUntil(snoozedUntil)

        XCTAssertEqual(
            ReminderStateStore(defaults: defaults).load(),
            ReminderState(lastFiredAt: firedAt, snoozedUntil: snoozedUntil)
        )

        store.saveSnoozedUntil(nil)

        XCTAssertEqual(
            store.load(),
            ReminderState(lastFiredAt: firedAt, snoozedUntil: nil)
        )
    }

    func testStateUsesDedicatedKeysWithoutMutatingReminderSettings() {
        let defaults = isolatedDefaults()
        defaults.set(22 * 60 + 35, forKey: AppSettingsStorageKey.dailyReminderMinutes)
        defaults.set(false, forKey: AppSettingsStorageKey.reminderEnabled)
        let store = ReminderStateStore(defaults: defaults)

        store.saveLastFiredAt(Date(timeIntervalSince1970: 100))
        store.saveSnoozedUntil(Date(timeIntervalSince1970: 700))

        XCTAssertEqual(
            defaults.integer(forKey: AppSettingsStorageKey.dailyReminderMinutes),
            22 * 60 + 35
        )
        XCTAssertFalse(defaults.bool(forKey: AppSettingsStorageKey.reminderEnabled))
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CornerPet.ReminderStateStoreTests.\(UUID().uuidString)")!
    }
}

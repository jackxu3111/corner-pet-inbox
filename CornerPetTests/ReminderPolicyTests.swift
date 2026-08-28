import Foundation
import XCTest

@testable import CornerPet

final class ReminderPolicyTests: XCTestCase {
    func testBeforeDailyTimeDoesNothingAndAtOrAfterTimePresentsNormalReminder() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let before = localDate(2026, 8, 29, 8, 59, calendar: calendar)
        let atTime = localDate(2026, 8, 29, 9, 0, calendar: calendar)
        let after = localDate(2026, 8, 29, 14, 20, calendar: calendar)

        XCTAssertEqual(evaluate(at: before, calendar: calendar), .none)
        XCTAssertEqual(
            evaluate(at: atTime, calendar: calendar),
            .presentNormal(firedAt: atTime)
        )
        XCTAssertEqual(
            evaluate(at: after, calendar: calendar),
            .presentNormal(firedAt: after)
        )
    }

    func testNormalReminderIsSuppressedWhenAlreadyHandledInSameLocalDay() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let now = localDate(2026, 8, 29, 18, 0, calendar: calendar)
        let firedAt = localDate(2026, 8, 29, 9, 0, calendar: calendar)

        XCTAssertEqual(
            evaluate(
                at: now,
                state: ReminderState(lastFiredAt: firedAt, snoozedUntil: nil),
                calendar: calendar
            ),
            .none
        )
    }

    func testDisabledReminderClearsOutstandingSnooze() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let now = localDate(2026, 8, 29, 18, 0, calendar: calendar)
        let snoozedUntil = now.addingTimeInterval(600)

        XCTAssertEqual(
            evaluate(
                at: now,
                configuration: ReminderConfiguration(isEnabled: false, dailyMinutes: 540),
                state: ReminderState(lastFiredAt: nil, snoozedUntil: snoozedUntil),
                calendar: calendar
            ),
            .clearSnooze
        )
        XCTAssertEqual(
            evaluate(
                at: now,
                configuration: ReminderConfiguration(isEnabled: false, dailyMinutes: 540),
                calendar: calendar
            ),
            .none
        )
    }

    func testVisiblePanelsPreventConflictingOrDuplicatePresentation() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let now = localDate(2026, 8, 29, 9, 0, calendar: calendar)

        XCTAssertEqual(
            evaluate(at: now, calendar: calendar, isCaptureVisible: true),
            .handleNormalWithoutPresentation(firedAt: now)
        )
        XCTAssertEqual(
            evaluate(at: now, calendar: calendar, isReminderVisible: true),
            .none
        )
    }

    func testDueSnoozeTakesPriorityAndIsConsumedWhenCaptureIsVisible() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let firedAt = localDate(2026, 8, 29, 9, 0, calendar: calendar)
        let snoozedUntil = firedAt.addingTimeInterval(600)
        let state = ReminderState(lastFiredAt: firedAt, snoozedUntil: snoozedUntil)

        XCTAssertEqual(
            evaluate(
                at: snoozedUntil.addingTimeInterval(-1),
                state: state,
                calendar: calendar
            ),
            .none
        )
        XCTAssertEqual(
            evaluate(at: snoozedUntil, state: state, calendar: calendar),
            .presentSnoozed
        )
        XCTAssertEqual(
            evaluate(
                at: snoozedUntil,
                state: state,
                calendar: calendar,
                isCaptureVisible: true
            ),
            .consumeSnoozeWithoutPresentation
        )
    }

    func testFutureSnoozeSuppressesNormalReminderUntilItsDeadline() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let now = localDate(2026, 8, 29, 9, 0, calendar: calendar)
        let snoozedUntil = now.addingTimeInterval(300)

        XCTAssertEqual(
            evaluate(
                at: now,
                state: ReminderState(lastFiredAt: nil, snoozedUntil: snoozedUntil),
                calendar: calendar
            ),
            .none
        )
    }

    func testSnoozeDeadlineRemainsAbsoluteAcrossMidnight() {
        let calendar = calendar(timeZoneID: "Asia/Shanghai")
        let firedAt = localDate(2026, 8, 29, 23, 55, calendar: calendar)
        let snoozedUntil = firedAt.addingTimeInterval(600)
        let state = ReminderState(lastFiredAt: firedAt, snoozedUntil: snoozedUntil)

        XCTAssertEqual(
            calendar.dateComponents([.day, .hour, .minute], from: snoozedUntil),
            DateComponents(day: 30, hour: 0, minute: 5)
        )
        XCTAssertEqual(
            evaluate(at: snoozedUntil, state: state, calendar: calendar),
            .presentSnoozed
        )
    }

    func testLastFiredDateIsReinterpretedUsingCurrentTimeZone() {
        let shanghai = calendar(timeZoneID: "Asia/Shanghai")
        let losAngeles = calendar(timeZoneID: "America/Los_Angeles")
        let lastFiredAt = isoDate("2026-08-29T00:30:00Z")
        let now = isoDate("2026-08-29T17:00:00Z")
        let state = ReminderState(lastFiredAt: lastFiredAt, snoozedUntil: nil)

        XCTAssertEqual(evaluate(at: now, state: state, calendar: shanghai), .none)
        XCTAssertEqual(
            evaluate(at: now, state: state, calendar: losAngeles),
            .presentNormal(firedAt: now)
        )
    }

    func testSpringForwardMissingTimeAdvancesToNextValidTime() throws {
        let calendar = calendar(timeZoneID: "America/Los_Angeles")
        let day = localDate(2026, 3, 8, 0, 0, calendar: calendar)

        let scheduled = try XCTUnwrap(ReminderPolicy.scheduledDate(
            on: day,
            dailyMinutes: 2 * 60 + 30,
            calendar: calendar
        ))

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduled),
            DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 0)
        )
    }

    func testFallBackChoosesFirstOccurrenceAndSuppressesTheSecond() throws {
        let calendar = calendar(timeZoneID: "America/Los_Angeles")
        let day = localDate(2026, 11, 1, 0, 0, calendar: calendar)
        let scheduled = try XCTUnwrap(ReminderPolicy.scheduledDate(
            on: day,
            dailyMinutes: 1 * 60 + 30,
            calendar: calendar
        ))
        let firstOccurrence = isoDate("2026-11-01T08:30:00Z")
        let secondOccurrence = isoDate("2026-11-01T09:30:00Z")

        XCTAssertEqual(scheduled, firstOccurrence)
        XCTAssertEqual(
            evaluate(
                at: secondOccurrence,
                state: ReminderState(lastFiredAt: firstOccurrence, snoozedUntil: nil),
                calendar: calendar
            ),
            .none
        )
    }

    private func evaluate(
        at now: Date,
        configuration: ReminderConfiguration = ReminderConfiguration(
            isEnabled: true,
            dailyMinutes: 540
        ),
        state: ReminderState = ReminderState(lastFiredAt: nil, snoozedUntil: nil),
        calendar: Calendar,
        isCaptureVisible: Bool = false,
        isReminderVisible: Bool = false
    ) -> ReminderDecision {
        ReminderPolicy.evaluate(ReminderPolicyInput(
            now: now,
            configuration: configuration,
            state: state,
            calendar: calendar,
            isCaptureVisible: isCaptureVisible,
            isReminderVisible: isReminderVisible
        ))
    }

    private func calendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

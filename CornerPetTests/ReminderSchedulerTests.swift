import Foundation
import XCTest

@testable import CornerPet

@MainActor
private final class ReminderDateBox {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

@MainActor
private final class FakeReminderStateStore: ReminderStateStoring {
    var state: ReminderState
    var onSave: ((String) -> Void)?

    init(state: ReminderState = ReminderState(lastFiredAt: nil, snoozedUntil: nil)) {
        self.state = state
    }

    func load() -> ReminderState {
        state
    }

    func saveLastFiredAt(_ date: Date?) {
        state = ReminderState(lastFiredAt: date, snoozedUntil: state.snoozedUntil)
        onSave?("lastFiredAt")
    }

    func saveSnoozedUntil(_ date: Date?) {
        state = ReminderState(lastFiredAt: state.lastFiredAt, snoozedUntil: date)
        onSave?("snoozedUntil")
    }
}

@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private let wakeNotification = Notification.Name("CornerPetTests.didWake")

    func testStartEvaluatesLaunchAndSchedulesOneMinuteWhileEnabled() {
        let fixture = makeFixture(now: localDate(2026, 8, 29, 8, 0))

        fixture.scheduler.start(configuration: enabledConfiguration)

        XCTAssertTrue(fixture.scheduler.isRunning)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .launch)
        XCTAssertEqual(fixture.timer.scheduledDelays, [60])
        XCTAssertEqual(fixture.presentations, [])
    }

    func testDisabledStartClearsSnoozeWithoutSchedulingMinuteEvaluation() {
        let now = localDate(2026, 8, 29, 8, 0)
        let fixture = makeFixture(
            now: now,
            state: ReminderState(lastFiredAt: nil, snoozedUntil: now.addingTimeInterval(600))
        )

        fixture.scheduler.start(configuration: ReminderConfiguration(
            isEnabled: false,
            dailyMinutes: 540
        ))

        XCTAssertNil(fixture.store.state.snoozedUntil)
        XCTAssertTrue(fixture.timer.scheduledDelays.isEmpty)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .launch)
    }

    func testConfigurationUpdatesCancelAndRestoreMinuteEvaluation() throws {
        let fixture = makeFixture(now: localDate(2026, 8, 29, 8, 0))
        fixture.scheduler.start(configuration: enabledConfiguration)
        let firstToken = try XCTUnwrap(fixture.timer.tokens.first)

        fixture.scheduler.update(configuration: ReminderConfiguration(
            isEnabled: false,
            dailyMinutes: 540
        ))

        XCTAssertTrue(firstToken.isCancelled)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .settingsChanged)

        fixture.scheduler.update(configuration: ReminderConfiguration(
            isEnabled: true,
            dailyMinutes: 600
        ))

        XCTAssertEqual(fixture.timer.scheduledDelays, [60, 60])
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .settingsChanged)
    }

    func testMovingReminderTimeBeforeNowEvaluatesTheNewScheduleImmediately() {
        let now = localDate(2026, 8, 29, 10, 0)
        let fixture = makeFixture(now: now)
        fixture.scheduler.start(configuration: ReminderConfiguration(
            isEnabled: true,
            dailyMinutes: 11 * 60
        ))

        fixture.scheduler.update(configuration: ReminderConfiguration(
            isEnabled: true,
            dailyMinutes: 9 * 60
        ))

        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .settingsChanged)
        XCTAssertEqual(fixture.presentations, [.normal])
        XCTAssertEqual(fixture.store.state.lastFiredAt, now)
    }

    func testNormalReminderPersistsBeforePresentation() {
        let fixture = makeFixture(now: localDate(2026, 8, 29, 10, 0))
        fixture.store.onSave = { fixture.events.append($0) }

        fixture.scheduler.start(configuration: enabledConfiguration)

        XCTAssertEqual(fixture.events, ["lastFiredAt", "present.normal"])
        XCTAssertEqual(fixture.store.state.lastFiredAt, fixture.dateBox.value)
        XCTAssertEqual(fixture.presentations, [.normal])
    }

    func testDueSnoozeClearsBeforePresentation() {
        let now = localDate(2026, 8, 29, 9, 10)
        let fixture = makeFixture(
            now: now,
            state: ReminderState(
                lastFiredAt: localDate(2026, 8, 29, 9, 0),
                snoozedUntil: now
            )
        )
        fixture.store.onSave = { fixture.events.append($0) }

        fixture.scheduler.start(configuration: enabledConfiguration)

        XCTAssertEqual(fixture.events, ["snoozedUntil", "present.snoozed"])
        XCTAssertNil(fixture.store.state.snoozedUntil)
        XCTAssertEqual(fixture.presentations, [.snoozed])
    }

    func testRepeatedWakeAfterSchedulePresentsOnlyOnce() {
        let fixture = makeFixture(now: localDate(2026, 8, 29, 8, 0))
        fixture.scheduler.start(configuration: enabledConfiguration)
        fixture.dateBox.value = localDate(2026, 8, 29, 10, 0)

        fixture.workspaceCenter.post(name: wakeNotification, object: nil)
        fixture.workspaceCenter.post(name: wakeNotification, object: nil)

        XCTAssertEqual(fixture.presentations, [.normal])
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .wake)
    }

    func testCalendarClockAndTimeZoneNotificationsEvaluateImmediately() {
        let fixture = makeFixture(now: localDate(2026, 8, 29, 8, 0))
        fixture.scheduler.start(configuration: enabledConfiguration)

        fixture.defaultCenter.post(name: .NSCalendarDayChanged, object: nil)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .calendarChanged)

        fixture.defaultCenter.post(name: .NSSystemClockDidChange, object: nil)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .clockChanged)

        fixture.defaultCenter.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .timeZoneChanged)
    }

    func testSnoozeStoresExactlyTenMinutesAndCompletionClearsIt() {
        let now = localDate(2026, 8, 29, 9, 0)
        let fixture = makeFixture(now: now)
        fixture.scheduler.start(configuration: enabledConfiguration)

        fixture.scheduler.snooze()

        XCTAssertEqual(fixture.store.state.snoozedUntil, now.addingTimeInterval(600))

        fixture.scheduler.completeCurrentReminder()

        XCTAssertNil(fixture.store.state.snoozedUntil)
    }

    func testStopCancelsTimerAndRemovesAllObservers() throws {
        let fixture = makeFixture(now: localDate(2026, 8, 29, 8, 0))
        fixture.scheduler.start(configuration: enabledConfiguration)
        let token = try XCTUnwrap(fixture.timer.tokens.first)

        fixture.scheduler.stop()
        fixture.workspaceCenter.post(name: wakeNotification, object: nil)
        fixture.defaultCenter.post(name: .NSSystemClockDidChange, object: nil)

        XCTAssertFalse(fixture.scheduler.isRunning)
        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(fixture.scheduler.lastEvaluationReason, .launch)
    }

    private var enabledConfiguration: ReminderConfiguration {
        ReminderConfiguration(isEnabled: true, dailyMinutes: 540)
    }

    private func makeFixture(
        now: Date,
        state: ReminderState = ReminderState(lastFiredAt: nil, snoozedUntil: nil)
    ) -> ReminderSchedulerFixture {
        let dateBox = ReminderDateBox(now)
        let store = FakeReminderStateStore(state: state)
        let timer = ManualDeadlineScheduler()
        let defaultCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let fixture = ReminderSchedulerFixture(
            dateBox: dateBox,
            store: store,
            timer: timer,
            defaultCenter: defaultCenter,
            workspaceCenter: workspaceCenter
        )
        fixture.scheduler = ReminderScheduler(
            stateStore: store,
            clock: { dateBox.value },
            calendarProvider: { self.calendar },
            timerScheduler: timer,
            defaultNotificationCenter: defaultCenter,
            workspaceNotificationCenter: workspaceCenter,
            wakeNotification: wakeNotification,
            isCaptureVisible: { false },
            isReminderVisible: { false },
            onPresent: { presentation in
                fixture.presentations.append(presentation)
                fixture.events.append("present.\(presentation == .normal ? "normal" : "snoozed")")
            }
        )
        return fixture
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
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
}

@MainActor
private final class ReminderSchedulerFixture {
    let dateBox: ReminderDateBox
    let store: FakeReminderStateStore
    let timer: ManualDeadlineScheduler
    let defaultCenter: NotificationCenter
    let workspaceCenter: NotificationCenter
    var presentations: [ReminderPresentation] = []
    var events: [String] = []
    var scheduler: ReminderScheduler!

    init(
        dateBox: ReminderDateBox,
        store: FakeReminderStateStore,
        timer: ManualDeadlineScheduler,
        defaultCenter: NotificationCenter,
        workspaceCenter: NotificationCenter
    ) {
        self.dateBox = dateBox
        self.store = store
        self.timer = timer
        self.defaultCenter = defaultCenter
        self.workspaceCenter = workspaceCenter
    }
}

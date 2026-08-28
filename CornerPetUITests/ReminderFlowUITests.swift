import AppKit
import XCTest

@MainActor
final class ReminderFlowUITests: XCTestCase {
    func testReminderOffersSnoozeAndDismissActions() {
        let app = launchReminder(corner: "topLeft")
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["reminder.openInbox"].exists)
        XCTAssertTrue(app.buttons["reminder.snooze"].exists)
        let dismiss = app.buttons["reminder.dismissToday"]
        XCTAssertTrue(dismiss.exists)

        dismiss.click()
        XCTAssertTrue(reminderPanel(in: app).waitForNonExistence(timeout: 2))
    }

    func testOpenInboxDismissesReminderAndOpensInbox() {
        let app = launchReminder(corner: "topRight")
        defer { app.terminate() }

        app.buttons["reminder.openInbox"].click()

        XCTAssertTrue(reminderPanel(in: app).waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.scrollViews["inbox.list"].waitForExistence(timeout: 5))
    }

    func testSnoozeDismissesCurrentReminder() {
        let app = launchReminder(corner: "bottomLeft")
        defer { app.terminate() }

        app.buttons["reminder.snooze"].click()

        XCTAssertTrue(reminderPanel(in: app).waitForNonExistence(timeout: 2))
    }

    func testReminderRailFollowsAllFourConfiguredCorners() throws {
        for corner in ["topLeft", "topRight", "bottomLeft", "bottomRight"] {
            let app = launchReminder(corner: corner)
            let frame = reminderPanel(in: app).frame
            let screenSize = try XCTUnwrap(NSScreen.main?.frame.size)

            if corner.hasSuffix("Left") {
                XCTAssertLessThan(frame.minX, 4, corner)
            } else {
                XCTAssertLessThan(abs(frame.maxX - screenSize.width), 4, corner)
            }
            if corner.hasPrefix("top") {
                XCTAssertGreaterThanOrEqual(frame.minY, 80, corner)
                XCTAssertLessThan(frame.minY, 160, corner)
            } else {
                XCTAssertGreaterThanOrEqual(screenSize.height - frame.maxY, 80, corner)
                XCTAssertLessThan(screenSize.height - frame.maxY, 160, corner)
            }
            app.terminate()
        }
    }

    private func launchReminder(corner: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-ui-show-reminder",
            "--cornerpet-ui-reminder-corner=\(corner)"
        ]
        app.launch()
        XCTAssertTrue(reminderPanel(in: app).waitForExistence(timeout: 5), corner)
        return app
    }

    private func reminderPanel(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["reminder.panel"]
    }
}

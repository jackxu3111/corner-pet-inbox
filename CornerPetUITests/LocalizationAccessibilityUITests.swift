import AppKit
import XCTest

@MainActor
final class LocalizationAccessibilityUITests: XCTestCase {
    func testEnglishCaptureExposesLocalizedVisibleAndAccessibilityCopy() throws {
        let app = launchCapture(language: "en")
        defer { app.terminate() }

        let input = app.textViews["capture.input"]
        XCTAssertEqual(input.label, "Capture a thought")
        XCTAssertTrue(app.staticTexts["Idea Inbox"].exists)
        XCTAssertTrue(app.staticTexts["No ideas yet"].exists)
        XCTAssertEqual(app.buttons["nav.inbox"].label, "Inbox")
        XCTAssertEqual(app.buttons["nav.favorites"].label, "Favorites")
        XCTAssertEqual(app.buttons["nav.archive"].label, "Archive")
        XCTAssertEqual(app.buttons["nav.settings"].label, "Settings")
        let pin = app.buttons["capture.pin"]
        XCTAssertEqual(pin.label, "Pin")
        XCTAssertGreaterThan(input.frame.width, 0)
        XCTAssertGreaterThan(input.frame.height, 0)
        XCTAssertTrue(pin.isEnabled)
        XCTAssertTrue(pin.isHittable)

        input.click()
        input.typeText("accessible idea")
        input.hover()
        input.typeKey(.return, modifierFlags: [])
        let idea = app.staticTexts["accessible idea"]
        XCTAssertTrue(idea.waitForExistence(timeout: 2))
        XCTAssertEqual(firstButton(prefix: "inbox.item.complete.", in: app).label, "Complete and archive")
        XCTAssertEqual(firstButton(prefix: "inbox.item.favorite.", in: app).label, "Add to Favorites")
        XCTAssertEqual(firstButton(prefix: "inbox.item.delete.", in: app).label, "Delete permanently")
        try app.performAccessibilityAudit(for: .action)

        idea.doubleClick()
        let editor = app.textViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.editor.")
        ).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertEqual(editor.label, "Edit idea")
    }

    func testSimplifiedChineseCaptureExposesLocalizedVisibleAndAccessibilityCopy() {
        let app = launchCapture(language: "zh-Hans")
        defer { app.terminate() }

        let input = app.textViews["capture.input"]
        XCTAssertEqual(input.label, "记下想法")
        XCTAssertTrue(app.staticTexts["角落灵感箱"].exists)
        XCTAssertTrue(app.staticTexts["还没有想法"].exists)
        XCTAssertEqual(app.buttons["nav.inbox"].label, "收件箱")
        XCTAssertEqual(app.buttons["nav.favorites"].label, "收藏")
        XCTAssertEqual(app.buttons["nav.archive"].label, "归档")
        XCTAssertEqual(app.buttons["nav.settings"].label, "设置")
        XCTAssertEqual(app.buttons["capture.pin"].label, "置顶")
    }

    func testLanguagePickerUpdatesSettingsCaptureAndAppKitLabelsWithoutRestart() {
        let app = launchCapture(language: "en")
        defer { app.terminate() }
        let input = app.textViews["capture.input"]

        app.buttons["nav.settings"].click()
        let languagePicker = element("settings.language", in: app)
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 3))
        XCTAssertTrue(element("settings.language.help", in: app).exists)
        XCTAssertTrue(app.staticTexts["Changes apply immediately across the app."].exists)

        languagePicker.click()
        let simplifiedChinese = app.menuItems["Simplified Chinese"]
        XCTAssertTrue(simplifiedChinese.waitForExistence(timeout: 2))
        simplifiedChinese.click()

        XCTAssertTrue(waitForLabel("记下想法", on: input))
        XCTAssertTrue(app.staticTexts["更改会立即应用于整个应用。"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForLabel("收件箱", on: app.buttons["nav.inbox"]))

        input.click()
        input.typeText("即时语言想法")
        input.hover()
        input.typeKey(.return, modifierFlags: [])
        let idea = app.staticTexts["即时语言想法"]
        XCTAssertTrue(idea.waitForExistence(timeout: 2))
        idea.doubleClick()
        let editor = app.textViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.editor.")
        ).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertEqual(editor.label, "编辑想法")
    }

    func testSimplifiedChineseReminderHasNamedEnabledActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=zh-Hans",
            "--cornerpet-memory-store",
            "--cornerpet-ui-show-reminder",
            "--cornerpet-ui-reminder-corner=topLeft"
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(element("reminder.panel", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["该看看收件箱啦"].exists)
        XCTAssertEqual(app.buttons["reminder.openInbox"].label, "打开收件箱")
        XCTAssertEqual(app.buttons["reminder.snooze"].label, "10 分钟后提醒")
        XCTAssertEqual(app.buttons["reminder.dismissToday"].label, "今天不再提醒")
        XCTAssertTrue(app.buttons["reminder.openInbox"].isEnabled)
        XCTAssertTrue(app.buttons["reminder.snooze"].isEnabled)
        XCTAssertTrue(app.buttons["reminder.dismissToday"].isEnabled)
    }

    private func launchCapture(language: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=\(language)",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture",
            "--cornerpet-ui-keep-capture-open"
        ]
        app.launch()
        let firstDialog = app.dialogs.firstMatch
        XCTAssertTrue(firstDialog.waitForExistence(timeout: 2))
        let triggerZone = app.dialogs.allElementsBoundByIndex.min {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        } ?? firstDialog
        triggerZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.hover()
        return app
    }

    private func firstButton(prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        ).firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForLabel(
        _ label: String,
        on element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

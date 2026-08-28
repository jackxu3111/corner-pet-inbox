import XCTest

@MainActor
final class CaptureFlowUITests: XCTestCase {
    func testCaptureReturnAddsNewestItemAndKeepsFixedShellVisible() {
        let app = launchApp()
        defer { app.terminate() }
        let input = captureInput(in: app)
        input.click()
        input.typeText("first idea")
        input.hover()

        input.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["first idea"].waitForExistence(timeout: 2))
        XCTAssertTrue(element("capture.header", in: app).exists)
        XCTAssertTrue(app.scrollViews["inbox.list"].exists)
        XCTAssertTrue(app.buttons["nav.inbox"].exists)
    }

    func testCompletingItemMovesItFromInboxToArchive() {
        let app = launchApp()
        defer { app.terminate() }
        let input = captureInput(in: app)
        input.click()
        input.typeText("complete this")
        input.hover()
        input.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["complete this"].waitForExistence(timeout: 2))

        let completionButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.complete.")
        ).firstMatch
        XCTAssertTrue(completionButton.waitForExistence(timeout: 1))

        completionButton.click()

        XCTAssertTrue(app.staticTexts["complete this"].waitForNonExistence(timeout: 2))

        app.buttons["nav.archive"].click()

        XCTAssertTrue(app.scrollViews["archive.list"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["complete this"].waitForExistence(timeout: 2))
    }

    func testShiftReturnKeepsMultilineDraftThenReturnSubmits() {
        let app = launchApp()
        defer { app.terminate() }
        let input = captureInput(in: app)
        input.click()
        input.typeText("line one")
        input.typeKey(.return, modifierFlags: .shift)
        input.typeText("line two")

        XCTAssertEqual(input.value as? String, "line one\nline two")

        input.hover()
        input.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["line one\nline two"].waitForExistence(timeout: 2))
        XCTAssertEqual(input.value as? String, "")
    }

    func testEscapeClosesAndReopenRestoresDraft() {
        let app = launchApp()
        defer { app.terminate() }
        let input = captureInput(in: app)
        input.click()
        input.typeText("draft survives")

        input.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(input.waitForNonExistence(timeout: 2))

        let triggerZone = app.dialogs.element(boundBy: 0)
        XCTAssertTrue(triggerZone.waitForExistence(timeout: 1))
        triggerZone.coordinate(
            withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)
        ).hover()

        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "draft survives")
    }

    func testBottomNavigationShowsFavoritesAndSettingsPlaceholder() {
        let app = launchApp()
        defer { app.terminate() }
        _ = captureInput(in: app)

        app.buttons["nav.favorites"].click()
        XCTAssertTrue(app.scrollViews["favorites.list"].waitForExistence(timeout: 1))
        XCTAssertFalse(element("placeholder.favorites", in: app).exists)
        XCTAssertFalse(app.scrollViews["inbox.list"].exists)
        XCTAssertFalse(app.buttons["inbox.error.retry"].exists)

        app.buttons["nav.settings"].click()
        XCTAssertTrue(element("placeholder.settings", in: app).waitForExistence(timeout: 1))
        XCTAssertFalse(app.scrollViews["inbox.list"].exists)
        XCTAssertFalse(app.buttons["inbox.error.retry"].exists)

        app.buttons["nav.inbox"].click()

        XCTAssertTrue(app.scrollViews["inbox.list"].waitForExistence(timeout: 1))
        XCTAssertFalse(element("placeholder.favorites", in: app).exists)
        XCTAssertFalse(element("placeholder.archive", in: app).exists)
        XCTAssertFalse(element("placeholder.settings", in: app).exists)
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture"
        ]
        app.launch()
        return app
    }

    private func captureInput(in app: XCUIApplication) -> XCUIElement {
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        return input
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}

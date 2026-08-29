import AppKit
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

        XCTAssertTrue(
            app.scrollViews["inbox.list"].staticTexts["complete this"]
                .waitForNonExistence(timeout: 2)
        )

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
        let app = launchApp(keepsCaptureOpen: false)
        defer { app.terminate() }
        let input = captureInput(in: app)
        input.click()
        input.typeText("draft survives")

        let panel = app.descendants(matching: .any)["capture.panel"]
        let panelFrame = panel.frame
        let outsideX = panelFrame.minX > 100
            ? panelFrame.minX - 40
            : panelFrame.maxX + 40
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(
                dx: outsideX - panelFrame.minX,
                dy: panelFrame.midY - panelFrame.minY
            ))
            .hover()
        input.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(input.waitForNonExistence(timeout: 2))

        let firstDialog = app.dialogs.firstMatch
        XCTAssertTrue(firstDialog.waitForExistence(timeout: 1))
        let triggerZone = app.dialogs.allElementsBoundByIndex.min {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        } ?? firstDialog
        triggerZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()

        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "draft survives")
    }

    func testBottomNavigationShowsFavoritesAndReturnsToInbox() {
        let app = launchApp()
        defer { app.terminate() }
        _ = captureInput(in: app)

        app.buttons["nav.favorites"].click()
        XCTAssertTrue(app.scrollViews["favorites.list"].waitForExistence(timeout: 1))
        XCTAssertFalse(element("placeholder.favorites", in: app).exists)
        XCTAssertFalse(app.scrollViews["inbox.list"].exists)
        XCTAssertFalse(app.buttons["inbox.error.retry"].exists)

        app.buttons["nav.inbox"].click()

        XCTAssertTrue(app.scrollViews["inbox.list"].waitForExistence(timeout: 1))
        XCTAssertFalse(element("placeholder.favorites", in: app).exists)
        XCTAssertFalse(element("placeholder.archive", in: app).exists)
        XCTAssertFalse(element("placeholder.settings", in: app).exists)
    }

    func testSettingsEntryOpensNativeSettingsControls() {
        let app = launchApp()
        defer { app.terminate() }
        _ = captureInput(in: app)
        app.buttons["nav.settings"].click()

        XCTAssertTrue(element("settings.triggerCorner", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("settings.displayScope", in: app).exists)
        XCTAssertTrue(element("settings.reminderEnabled", in: app).exists)
        XCTAssertTrue(element("settings.reminderTime", in: app).exists)
        XCTAssertTrue(element("settings.language", in: app).exists)
        XCTAssertTrue(element("settings.launchAtLogin", in: app).exists)
        XCTAssertTrue(element("settings.conflictHelp.body", in: app).exists)

        let reminderToggle = element("settings.reminderEnabled", in: app)
        let reminderTime = element("settings.reminderTime", in: app)
        XCTAssertTrue(reminderTime.isEnabled)
        reminderToggle.click()
        XCTAssertFalse(reminderTime.isEnabled)
    }

    func testConflictHelpIsVisibleWithoutExpandingAnything() {
        let app = launchApp()
        defer { app.terminate() }
        _ = captureInput(in: app)
        app.buttons["nav.settings"].click()

        XCTAssertTrue(element("settings.conflictHelp.body", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("settings.conflictHelp.openSystemSettings", in: app).exists)
    }

    private func launchApp(keepsCaptureOpen: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture"
        ]
        if keepsCaptureOpen {
            app.launchArguments.append("--cornerpet-ui-keep-capture-open")
        }
        app.launch()
        keepPointerInsideCapturePanel(in: app)
        return app
    }

    private func keepPointerInsideCapturePanel(in app: XCUIApplication) {
        let firstDialog = app.dialogs.firstMatch
        XCTAssertTrue(firstDialog.waitForExistence(timeout: 2))
        let triggerZone = app.dialogs.allElementsBoundByIndex.min {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        } ?? firstDialog
        triggerZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()

        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.hover()
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

@MainActor
final class SettingsShortcutUITests: XCTestCase {
    func testCommandCommaFromCapturePanelOpensSettings() {
        continueAfterFailure = false
        let existingProcessIdentifiers = Set(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.jack.CornerPet"
            ).map(\.processIdentifier)
        )
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-ui-open-capture-without-activation",
            "--cornerpet-ui-keep-capture-open",
            "--cornerpet-ui-command-comma-signal"
        ]
        app.launch()
        defer { app.terminate() }

        let input = app.textViews["capture.input"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("The nonactivating CornerPet capture panel did not appear")
            return
        }
        let launchedApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.jack.CornerPet"
        ).filter { !existingProcessIdentifiers.contains($0.processIdentifier) }
        guard launchedApplications.count == 1,
              let runningApp = launchedApplications.first else {
            XCTFail("Expected exactly one newly launched CornerPet process")
            return
        }
        guard !runningApp.isActive else {
            XCTFail("The nonactivating capture fixture unexpectedly activated CornerPet")
            return
        }

        postCommandComma(to: runningApp.processIdentifier)

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.triggerCorner"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.descendants(matching: .any)["settings.conflictHelp.body"].exists)
    }

    private func postCommandComma(to processIdentifier: pid_t) {
        XCTAssertEqual(Darwin.kill(processIdentifier, SIGUSR1), 0)
    }
}

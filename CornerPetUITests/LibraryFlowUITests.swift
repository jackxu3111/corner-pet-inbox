import XCTest

@MainActor
final class LibraryFlowUITests: XCTestCase {
    func testArchiveUndoAndFavoriteUnfavoriteFlow() {
        let app = launchApp()
        defer { app.terminate() }

        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("library flow")
        input.hover()
        input.typeKey(.return, modifierFlags: [])

        let completion = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.complete.")
        ).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 2))
        completion.click()

        XCTAssertTrue(
            app.scrollViews["inbox.list"].staticTexts["library flow"]
                .waitForNonExistence(timeout: 2)
        )
        let undo = app.buttons["inbox.archive.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.click()
        XCTAssertTrue(app.staticTexts["library flow"].waitForExistence(timeout: 2))

        let favorite = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.favorite.")
        ).firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 2))
        favorite.click()

        app.buttons["nav.favorites"].click()
        XCTAssertTrue(app.scrollViews["favorites.list"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["library flow"].waitForExistence(timeout: 2))

        let unfavorite = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "favorites.item.unfavorite.")
        ).firstMatch
        XCTAssertTrue(unfavorite.exists)
        unfavorite.click()

        app.buttons["nav.inbox"].click()
        XCTAssertTrue(app.staticTexts["library flow"].waitForExistence(timeout: 2))
    }

    func testArchiveAndFavoritesSearchAndCommandF() {
        let app = launchApp()
        defer { app.terminate() }
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        input.click()
        input.typeText("archive-cmdf-coffee")
        input.hover()
        input.typeKey(.return, modifierFlags: [])
        let completion = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.complete.")
        ).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 2))
        completion.click()
        XCTAssertTrue(
            app.scrollViews["inbox.list"].staticTexts["archive-cmdf-coffee"]
                .waitForNonExistence(timeout: 2)
        )

        input.click()
        input.typeText("favorites-cmdf-cafe")
        input.hover()
        input.typeKey(.return, modifierFlags: [])
        let favorite = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.favorite.")
        ).firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 2))
        favorite.click()

        app.buttons["nav.archive"].click()
        let archiveSearch = app.textFields["archive.search"]
        XCTAssertTrue(archiveSearch.waitForExistence(timeout: 2))
        app.activate()
        app.buttons["nav.archive"].click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(waitForKeyboardFocus(on: archiveSearch))
        archiveSearch.typeText("archive-cmdf-coffee")
        XCTAssertEqual(archiveSearch.value as? String, "archive-cmdf-coffee")
        XCTAssertTrue(app.staticTexts["archive-cmdf-coffee"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["favorites-cmdf-cafe"].exists)

        app.typeKey("a", modifierFlags: .command)
        app.typeText("archive-cmdf-missing")
        XCTAssertEqual(archiveSearch.value as? String, "archive-cmdf-missing")
        XCTAssertTrue(
            app.descendants(matching: .any)["archive.empty"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts["archive-cmdf-coffee"].exists)

        app.buttons["nav.favorites"].click()
        let favoritesSearch = app.textFields["favorites.search"]
        XCTAssertTrue(favoritesSearch.waitForExistence(timeout: 2))
        app.activate()
        app.buttons["nav.favorites"].click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(waitForKeyboardFocus(on: favoritesSearch))
        favoritesSearch.typeText("FAVORITES-CMDF-CAFE")
        XCTAssertEqual(favoritesSearch.value as? String, "FAVORITES-CMDF-CAFE")
        XCTAssertTrue(app.staticTexts["favorites-cmdf-cafe"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["archive-cmdf-coffee"].exists)

        app.typeKey("a", modifierFlags: .command)
        app.typeText("favorites-cmdf-missing")
        XCTAssertEqual(favoritesSearch.value as? String, "favorites-cmdf-missing")
        XCTAssertTrue(
            app.descendants(matching: .any)["favorites.empty"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts["favorites-cmdf-cafe"].exists)
    }

    func testInlineEditReturnShiftReturnEscapeAndOutsideSave() {
        let app = launchApp()
        defer { app.terminate() }
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("editable")
        input.hover()
        input.typeKey(.return, modifierFlags: [])
        let itemRow = app.groups.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.")
        ).firstMatch
        XCTAssertTrue(itemRow.waitForExistence(timeout: 3))
        let row = itemRow.staticTexts["editable"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))

        row.doubleClick()
        let editor = app.textViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.editor.")
        ).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        let favorite = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.favorite.")
        ).firstMatch
        let delete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.delete.")
        ).firstMatch
        let complete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.complete.")
        ).firstMatch
        XCTAssertFalse(favorite.isEnabled)
        XCTAssertFalse(delete.isEnabled)
        XCTAssertFalse(complete.isEnabled)
        editor.click()
        XCTAssertTrue(waitForKeyboardFocus(on: editor))
        editor.typeText(" updated")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["editable updated"].waitForExistence(timeout: 5))

        app.staticTexts["editable updated"].doubleClick()
        let activeEditor = app.textViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.editor.")
        ).firstMatch
        XCTAssertTrue(activeEditor.waitForExistence(timeout: 2))
        activeEditor.click()
        XCTAssertTrue(waitForKeyboardFocus(on: activeEditor))
        app.typeKey(.return, modifierFlags: .shift)
        app.typeText("line")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["editable updated"].waitForExistence(timeout: 5))

        app.staticTexts["editable updated"].doubleClick()
        let outsideEditor = app.textViews.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.editor.")
        ).firstMatch
        XCTAssertTrue(outsideEditor.waitForExistence(timeout: 2))
        outsideEditor.click()
        XCTAssertTrue(waitForKeyboardFocus(on: outsideEditor))
        outsideEditor.typeText(" outside")
        input.click()
        XCTAssertTrue(app.staticTexts["editable updated outside"].waitForExistence(timeout: 2))
    }

    func testDeleteRequiresConfirmationAndCancelPreservesRow() {
        let app = launchApp()
        defer { app.terminate() }
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("delete candidate")
        input.hover()
        input.typeKey(.return, modifierFlags: [])

        let delete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.delete.")
        ).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.click()
        XCTAssertTrue(app.buttons["inbox.delete.confirm"].waitForExistence(timeout: 2))
        app.buttons["inbox.delete.cancel"].click()
        XCTAssertTrue(app.staticTexts["delete candidate"].exists)

        delete.click()
        XCTAssertTrue(app.buttons["inbox.delete.confirm"].waitForExistence(timeout: 2))
        app.buttons["inbox.delete.confirm"].click()
        XCTAssertTrue(app.staticTexts["delete candidate"].waitForNonExistence(timeout: 2))
    }

    func testDeleteFailureRetainsRowAndShowsAccessibleError() {
        let app = launchApp(arguments: ["--cornerpet-ui-delete-failure"])
        defer { app.terminate() }
        let input = app.textViews["capture.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("delete failure")
        input.hover()
        input.typeKey(.return, modifierFlags: [])

        let delete = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.delete.")
        ).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.click()
        XCTAssertTrue(app.buttons["inbox.delete.confirm"].waitForExistence(timeout: 2))
        app.buttons["inbox.delete.confirm"].click()

        XCTAssertTrue(app.staticTexts["删除失败 / Delete failed"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["delete failure"].exists)
        XCTAssertFalse(app.buttons["inbox.delete.confirm"].exists)
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture",
            "--cornerpet-ui-keep-capture-open"
        ] + arguments
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

    private func waitForKeyboardFocus(
        on element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

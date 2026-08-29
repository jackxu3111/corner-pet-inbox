import XCTest

@MainActor
final class PinningFlowUITests: XCTestCase {
    func testPinButtonTogglesPinnedState() {
        let app = launchApp()
        defer { app.terminate() }

        let pin = app.buttons["capture.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        pin.click()
        XCTAssertTrue(waitForLabel("Unpin", on: pin))

        pin.click()
        XCTAssertTrue(waitForLabel("Pin", on: pin))
    }

    func testCommandShiftPTogglesTheSamePinnedState() {
        let app = launchApp()
        defer { app.terminate() }

        let pin = app.buttons["capture.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLabel("Unpin", on: pin))
    }

    func testPinnedPanelRemainsVisibleAfterPointerLeavesTriggerArea() {
        let app = launchApp()
        defer { app.terminate() }

        let pin = app.buttons["capture.pin"]
        let panel = app.descendants(matching: .any)["capture.panel"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists)

        pin.click()
        XCTAssertTrue(waitForLabel("Unpin", on: pin))

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

        XCTAssertTrue(panel.waitForExistence(timeout: 1))
        XCTAssertTrue(pin.exists)
        XCTAssertTrue(waitForLabel("Unpin", on: pin))
    }

    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--cornerpet-ui-testing",
            "--cornerpet-ui-language=en",
            "--cornerpet-memory-store",
            "--cornerpet-open-capture"
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

    private func waitForLabel(
        _ label: String,
        on element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

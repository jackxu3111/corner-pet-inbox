import XCTest

@MainActor
final class PinningFlowUITests: XCTestCase {
    func testPinButtonTogglesPinnedState() {
        let app = launchApp()
        defer { app.terminate() }

        let pin = app.buttons["capture.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        pin.click()
        XCTAssertEqual(pin.label, "取消置顶 / Unpin")

        pin.click()
        XCTAssertEqual(pin.label, "置顶 / Pin")
    }

    func testCommandShiftPTogglesTheSamePinnedState() {
        let app = launchApp()
        defer { app.terminate() }

        let pin = app.buttons["capture.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        app.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertEqual(pin.label, "取消置顶 / Unpin")
    }

    func testPinnedPanelRemainsVisibleAfterPointerLeavesTriggerArea() {
        let app = launchApp()
        defer { app.terminate() }

        let pin = app.buttons["capture.pin"]
        let panel = app.otherElements["capture.panel"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists)

        pin.click()
        XCTAssertEqual(pin.label, "取消置顶 / Unpin")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)).hover()

        XCTAssertTrue(panel.waitForExistence(timeout: 1))
        XCTAssertTrue(pin.exists)
        XCTAssertEqual(pin.label, "取消置顶 / Unpin")
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
}

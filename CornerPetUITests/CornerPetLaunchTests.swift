import XCTest

final class CornerPetLaunchTests: XCTestCase {
    func testApplicationLaunchesWithoutMainWindow() {
        let app = XCUIApplication()
        app.launch()

        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertEqual(app.windows.count, 0)
        app.terminate()
    }
}

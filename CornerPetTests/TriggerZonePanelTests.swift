import AppKit
import XCTest

@testable import CornerPet

@MainActor
final class TriggerZonePanelTests: XCTestCase {
    func testTriggerPanelIsTransparentNonactivatingAndFullscreenAuxiliary() {
        let panel = TriggerZonePanel(frame: CGRect(x: 0, y: 0, width: 86, height: 20)) {}

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testTrackingAreaUsesBoundaryEventsInAllVisibleSpacesWithoutMouseMoved() throws {
        let panel = TriggerZonePanel(frame: CGRect(x: 0, y: 0, width: 86, height: 20)) {}
        let area = try XCTUnwrap(panel.trackingView.trackingAreas.first)

        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertFalse(area.options.contains(.mouseMoved))
    }

    func testTopLeftFramesUseExactArmDimensionsOnNegativeOriginScreen() {
        let frames = TriggerZonePanel.frames(
            for: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            corner: .topLeft
        )

        XCTAssertEqual(frames.horizontal, CGRect(x: -1512, y: 962, width: 86, height: 20))
        XCTAssertEqual(frames.vertical, CGRect(x: -1512, y: 896, width: 20, height: 86))
    }

    func testBoundaryCallbackCanBeForwardedByTrackingView() {
        var callbackCount = 0
        let panel = TriggerZonePanel(frame: .zero) {
            callbackCount += 1
        }

        panel.trackingView.onBoundaryChanged()

        XCTAssertEqual(callbackCount, 1)
    }
}

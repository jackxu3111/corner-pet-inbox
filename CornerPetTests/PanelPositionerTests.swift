import CoreGraphics
import XCTest

@testable import CornerPet

final class PanelPositionerTests: XCTestCase {
    func testReturnTargetUsesPanelCenterToChooseEveryPhysicalScreenCorner() throws {
        let screen = PanelScreenGeometry(
            id: 7,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760)
        )
        let fixtures: [(panelFrame: CGRect, corner: TriggerCorner, targetFrame: CGRect)] = [
            (
                CGRect(x: 50, y: 650, width: 100, height: 100),
                .topLeft,
                CGRect(x: 0, y: 660, width: 100, height: 100)
            ),
            (
                CGRect(x: 850, y: 650, width: 100, height: 100),
                .topRight,
                CGRect(x: 900, y: 660, width: 100, height: 100)
            ),
            (
                CGRect(x: 50, y: 50, width: 100, height: 100),
                .bottomLeft,
                CGRect(x: 0, y: 0, width: 100, height: 100)
            ),
            (
                CGRect(x: 850, y: 50, width: 100, height: 100),
                .bottomRight,
                CGRect(x: 900, y: 0, width: 100, height: 100)
            )
        ]

        for fixture in fixtures {
            let target = try XCTUnwrap(PanelPositioner.returnTarget(
                for: fixture.panelFrame,
                screens: [screen],
                currentScreenID: screen.id,
                currentCorner: .topLeft
            ))

            XCTAssertEqual(target.screenID, screen.id)
            XCTAssertEqual(target.corner, fixture.corner)
            XCTAssertEqual(target.frame, fixture.targetFrame)
        }
    }

    func testReturnTargetMeasuresPhysicalCornersButPlacesInsideVisibleFrame() throws {
        let screen = PanelScreenGeometry(
            id: 8,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 100, width: 1_000, height: 850)
        )

        let target = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 50, y: 460, width: 100, height: 100),
            screens: [screen],
            currentScreenID: screen.id,
            currentCorner: .bottomLeft
        ))

        XCTAssertEqual(target.corner, .topLeft)
        XCTAssertEqual(target.frame, CGRect(x: 0, y: 850, width: 100, height: 100))
    }

    func testReturnTargetTieKeepsCurrentCornerThenUsesFixedCornerOrder() throws {
        let screen = PanelScreenGeometry(
            id: 9,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760)
        )

        let allCornersTie = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 450, y: 350, width: 100, height: 100),
            screens: [screen],
            currentScreenID: screen.id,
            currentCorner: .bottomRight
        ))
        let topCornersTie = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 450, y: 650, width: 100, height: 100),
            screens: [screen],
            currentScreenID: screen.id,
            currentCorner: .bottomRight
        ))

        XCTAssertEqual(allCornersTie.corner, .bottomRight)
        XCTAssertEqual(topCornersTie.corner, .topLeft)
    }

    func testReturnTargetUsesLargestScreenIntersectionAndCurrentScreenForAreaTie() throws {
        let left = PanelScreenGeometry(
            id: 20,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760)
        )
        let right = PanelScreenGeometry(
            id: 10,
            frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 760)
        )

        let largestIntersection = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 850, y: 50, width: 400, height: 100),
            screens: [left, right],
            currentScreenID: left.id,
            currentCorner: .topLeft
        ))
        let currentScreenTie = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 900, y: 50, width: 200, height: 100),
            screens: [left, right],
            currentScreenID: left.id,
            currentCorner: .topLeft
        ))
        let stableIDTie = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 900, y: 50, width: 200, height: 100),
            screens: [left, right],
            currentScreenID: nil,
            currentCorner: .topLeft
        ))

        XCTAssertEqual(largestIntersection.screenID, right.id)
        XCTAssertEqual(currentScreenTie.screenID, left.id)
        XCTAssertEqual(stableIDTie.screenID, right.id)
    }

    func testReturnTargetWithoutIntersectionUsesNearestScreenAndEmptyScreensReturnNil() throws {
        let left = PanelScreenGeometry(
            id: 2,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        let right = PanelScreenGeometry(
            id: 1,
            frame: CGRect(x: 500, y: 0, width: 100, height: 100),
            visibleFrame: CGRect(x: 500, y: 0, width: 100, height: 100)
        )

        let target = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 300, y: 20, width: 20, height: 20),
            screens: [left, right],
            currentScreenID: left.id,
            currentCorner: .topLeft
        ))
        let currentScreenTie = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 290, y: 20, width: 20, height: 20),
            screens: [left, right],
            currentScreenID: left.id,
            currentCorner: .topLeft
        ))
        let stableIDTie = try XCTUnwrap(PanelPositioner.returnTarget(
            for: CGRect(x: 290, y: 20, width: 20, height: 20),
            screens: [left, right],
            currentScreenID: nil,
            currentCorner: .topLeft
        ))

        XCTAssertEqual(target.screenID, right.id)
        XCTAssertEqual(currentScreenTie.screenID, left.id)
        XCTAssertEqual(stableIDTie.screenID, right.id)
        XCTAssertNil(PanelPositioner.returnTarget(
            for: CGRect(x: 300, y: 20, width: 20, height: 20),
            screens: [],
            currentScreenID: left.id,
            currentCorner: .topLeft
        ))
    }

    func testDefaultPanelUsesLargerSizeFlushWithEveryVisibleCornerWithNegativeCoordinates() {
        let visibleFrame = CGRect(x: -1440, y: -40, width: 1440, height: 900)

        let expectations: [(corner: TriggerCorner, frame: CGRect)] = [
            (
                .topLeft,
                CGRect(x: -1440, y: 410, width: 360, height: 450)
            ),
            (
                .topRight,
                CGRect(x: -360, y: 410, width: 360, height: 450)
            ),
            (
                .bottomLeft,
                CGRect(x: -1440, y: -40, width: 360, height: 450)
            ),
            (
                .bottomRight,
                CGRect(x: -360, y: -40, width: 360, height: 450)
            )
        ]

        for expectation in expectations {
            XCTAssertEqual(
                PanelPositioner.frame(
                    inside: visibleFrame,
                    corner: expectation.corner
                ),
                expectation.frame,
                "Unexpected frame for (expectation.corner)"
            )
        }
    }

    func testCustomSizeRemainsFlushWithTheSelectedVisibleCorner() {
        let visibleFrame = CGRect(x: -20, y: -10, width: 600, height: 500)
        let panelSize = CGSize(width: 280, height: 320)

        XCTAssertEqual(
            PanelPositioner.frame(inside: visibleFrame, corner: .topRight, size: panelSize),
            CGRect(x: 300, y: 170, width: 280, height: 320)
        )
    }
}

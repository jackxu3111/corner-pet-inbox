import AppKit
import XCTest

@testable import CornerPet

@MainActor
private final class ReminderPointBox {
    var value: CGPoint

    init(_ value: CGPoint) {
        self.value = value
    }
}

@MainActor
final class PetReminderPanelControllerTests: XCTestCase {
    func testPresentationCreatesOneNonactivatingFullScreenEdgeRail() throws {
        let screen = snapshot(id: 101, x: 0, width: 1_440)
        let controller = makeController(pointer: CGPoint(x: 700, y: 500))

        controller.present(
            corner: .topLeft,
            screens: [screen],
            primaryDisplayID: screen.id
        )

        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.currentScreenID, screen.id)
        XCTAssertEqual(panel.frame.size, CGSize(width: 240, height: 300))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testRepeatedPresentationReusesTheSinglePanel() throws {
        let screen = snapshot(id: 101, x: 0, width: 1_440)
        let controller = makeController(pointer: CGPoint(x: 700, y: 500))

        controller.present(corner: .topLeft, screens: [screen], primaryDisplayID: screen.id)
        let firstPanel = try XCTUnwrap(controller.panel)
        controller.present(corner: .bottomRight, screens: [screen], primaryDisplayID: screen.id)

        XCTAssertTrue(firstPanel === controller.panel)
        XCTAssertEqual(controller.panel?.frame, CGRect(x: 1_200, y: 86, width: 240, height: 300))
    }

    func testDismissOrdersOutAndPreservesPanelForReuse() throws {
        let screen = snapshot(id: 101, x: 0, width: 1_440)
        let controller = makeController(pointer: CGPoint(x: 700, y: 500))
        controller.present(corner: .topLeft, screens: [screen], primaryDisplayID: screen.id)
        let panel = try XCTUnwrap(controller.panel)

        controller.dismiss()

        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.currentScreenID)
        XCTAssertTrue(panel === controller.panel)
    }

    func testVisibleRailRelocatesWhenItsDisplayDisconnects() {
        let point = ReminderPointBox(CGPoint(x: 2_000, y: 500))
        let primary = snapshot(id: 101, x: 0, width: 1_440)
        let secondary = snapshot(id: 202, x: 1_440, width: 1_920)
        let controller = makeController(pointerProvider: { point.value })
        controller.present(
            corner: .topRight,
            screens: [primary, secondary],
            primaryDisplayID: primary.id
        )
        point.value = CGPoint(x: 700, y: 500)

        controller.updatePlacement(
            corner: .bottomLeft,
            screens: [primary],
            primaryDisplayID: primary.id
        )

        XCTAssertEqual(controller.currentScreenID, primary.id)
        XCTAssertEqual(controller.panel?.frame, CGRect(x: 0, y: 86, width: 240, height: 300))
    }

    private func makeController(pointer: CGPoint) -> PetReminderPanelController {
        makeController(pointerProvider: { pointer })
    }

    private func makeController(
        pointerProvider: @escaping @MainActor () -> CGPoint
    ) -> PetReminderPanelController {
        PetReminderPanelController(
            pointerLocationProvider: pointerProvider,
            onOpenInbox: {},
            onSnooze: {},
            onDismissToday: {}
        )
    }

    private func snapshot(id: UInt32, x: CGFloat, width: CGFloat) -> ScreenSnapshot {
        ScreenSnapshot(
            id: id,
            frame: CGRect(x: x, y: 0, width: width, height: 1_080),
            visibleFrame: CGRect(x: x, y: 25, width: width, height: 1_030)
        )
    }
}

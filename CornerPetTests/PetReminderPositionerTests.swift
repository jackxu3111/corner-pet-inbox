import CoreGraphics
import XCTest

@testable import CornerPet

final class PetReminderPositionerTests: XCTestCase {
    func testEveryCornerUsesTheMatchingSideAndLeavesTriggerZoneClear() throws {
        let screen = ScreenSnapshot(
            id: 101,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let expectedFrames: [TriggerCorner: CGRect] = [
            .topLeft: CGRect(x: 0, y: 514, width: 240, height: 300),
            .topRight: CGRect(x: 1_200, y: 514, width: 240, height: 300),
            .bottomLeft: CGRect(x: 0, y: 86, width: 240, height: 300),
            .bottomRight: CGRect(x: 1_200, y: 86, width: 240, height: 300)
        ]

        for corner in TriggerCorner.allCases {
            let placement = try XCTUnwrap(PetReminderPositioner.placement(
                screens: [screen],
                primaryDisplayID: screen.id,
                pointerLocation: CGPoint(x: 700, y: 450),
                corner: corner
            ))

            XCTAssertEqual(placement.screenID, screen.id, "corner: \(corner)")
            XCTAssertEqual(placement.frame, expectedFrames[corner], "corner: \(corner)")
        }
    }

    func testPointerDisplayWinsEvenWhenAnotherDisplayIsPrimary() throws {
        let primary = screen(id: 101, x: 0, width: 1_440)
        let secondary = screen(id: 202, x: 1_440, width: 1_920)

        let placement = try XCTUnwrap(PetReminderPositioner.placement(
            screens: [primary, secondary],
            primaryDisplayID: primary.id,
            pointerLocation: CGPoint(x: 2_000, y: 500),
            corner: .topRight
        ))

        XCTAssertEqual(placement.screenID, secondary.id)
        XCTAssertEqual(placement.frame.maxX, secondary.visibleFrame.maxX)
    }

    func testPointerOutsideAllScreensFallsBackToPrimaryThenFirstScreen() throws {
        let first = screen(id: 101, x: 0, width: 1_440)
        let second = screen(id: 202, x: 1_440, width: 1_920)
        let pointer = CGPoint(x: -10_000, y: -10_000)

        let primaryPlacement = try XCTUnwrap(PetReminderPositioner.placement(
            screens: [first, second],
            primaryDisplayID: second.id,
            pointerLocation: pointer,
            corner: .bottomLeft
        ))
        let firstPlacement = try XCTUnwrap(PetReminderPositioner.placement(
            screens: [first, second],
            primaryDisplayID: 999,
            pointerLocation: pointer,
            corner: .bottomLeft
        ))

        XCTAssertEqual(primaryPlacement.screenID, second.id)
        XCTAssertEqual(firstPlacement.screenID, first.id)
    }

    func testSmallVisibleFrameClampsRailWithoutLeavingDisplay() throws {
        let screen = ScreenSnapshot(
            id: 101,
            frame: CGRect(x: 0, y: 0, width: 220, height: 260),
            visibleFrame: CGRect(x: 0, y: 30, width: 220, height: 200)
        )

        let placement = try XCTUnwrap(PetReminderPositioner.placement(
            screens: [screen],
            primaryDisplayID: screen.id,
            pointerLocation: CGPoint(x: 100, y: 100),
            corner: .topRight
        ))

        XCTAssertEqual(placement.frame, screen.visibleFrame)
    }

    private func screen(id: UInt32, x: CGFloat, width: CGFloat) -> ScreenSnapshot {
        ScreenSnapshot(
            id: id,
            frame: CGRect(x: x, y: 0, width: width, height: 1_080),
            visibleFrame: CGRect(x: x, y: 0, width: width, height: 1_055)
        )
    }
}

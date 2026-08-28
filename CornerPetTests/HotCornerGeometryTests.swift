import AppKit
import XCTest

@testable import CornerPet

final class HotCornerGeometryTests: XCTestCase {
    func testRegionsReturnExpectedArmsAndOverlapForEveryCorner() {
        let frame = CGRect(x: -100, y: 200, width: 1000, height: 800)
        let fixtures: [(corner: TriggerCorner, regions: [CGRect], overlap: CGRect)] = [
            (
                .topLeft,
                [
                    CGRect(x: -100, y: 980, width: 86, height: 20),
                    CGRect(x: -100, y: 914, width: 20, height: 86)
                ],
                CGRect(x: -100, y: 980, width: 20, height: 20)
            ),
            (
                .topRight,
                [
                    CGRect(x: 814, y: 980, width: 86, height: 20),
                    CGRect(x: 880, y: 914, width: 20, height: 86)
                ],
                CGRect(x: 880, y: 980, width: 20, height: 20)
            ),
            (
                .bottomLeft,
                [
                    CGRect(x: -100, y: 200, width: 86, height: 20),
                    CGRect(x: -100, y: 200, width: 20, height: 86)
                ],
                CGRect(x: -100, y: 200, width: 20, height: 20)
            ),
            (
                .bottomRight,
                [
                    CGRect(x: 814, y: 200, width: 86, height: 20),
                    CGRect(x: 880, y: 200, width: 20, height: 86)
                ],
                CGRect(x: 880, y: 200, width: 20, height: 20)
            )
        ]

        for fixture in fixtures {
            let regions = HotCornerGeometry.regions(frame: frame, corner: fixture.corner)

            XCTAssertEqual(regions, fixture.regions, "Unexpected regions for \(fixture.corner)")
            XCTAssertEqual(regions[0].intersection(regions[1]), fixture.overlap)
        }
    }

    func testContainsIncludesClosedBoundaryAndOverlapPointsForEveryCorner() {
        let frame = CGRect(x: -100, y: 200, width: 1000, height: 800)
        let fixtures: [(corner: TriggerCorner, label: String, point: CGPoint)] = [
            (.topLeft, "physical corner", CGPoint(x: -100, y: 1000)),
            (.topLeft, "horizontal far end", CGPoint(x: -14, y: 1000)),
            (.topLeft, "horizontal inner long edge", CGPoint(x: -75, y: 980)),
            (.topLeft, "vertical far end", CGPoint(x: -100, y: 914)),
            (.topLeft, "vertical inner long edge", CGPoint(x: -80, y: 975)),
            (.topLeft, "overlap", CGPoint(x: -80, y: 980)),
            (.topRight, "physical corner", CGPoint(x: 900, y: 1000)),
            (.topRight, "horizontal far end", CGPoint(x: 814, y: 1000)),
            (.topRight, "horizontal inner long edge", CGPoint(x: 875, y: 980)),
            (.topRight, "vertical far end", CGPoint(x: 900, y: 914)),
            (.topRight, "vertical inner long edge", CGPoint(x: 880, y: 975)),
            (.topRight, "overlap", CGPoint(x: 880, y: 980)),
            (.bottomLeft, "physical corner", CGPoint(x: -100, y: 200)),
            (.bottomLeft, "horizontal far end", CGPoint(x: -14, y: 200)),
            (.bottomLeft, "horizontal inner long edge", CGPoint(x: -75, y: 220)),
            (.bottomLeft, "vertical far end", CGPoint(x: -100, y: 286)),
            (.bottomLeft, "vertical inner long edge", CGPoint(x: -80, y: 225)),
            (.bottomLeft, "overlap", CGPoint(x: -80, y: 220)),
            (.bottomRight, "physical corner", CGPoint(x: 900, y: 200)),
            (.bottomRight, "horizontal far end", CGPoint(x: 814, y: 200)),
            (.bottomRight, "horizontal inner long edge", CGPoint(x: 875, y: 220)),
            (.bottomRight, "vertical far end", CGPoint(x: 900, y: 286)),
            (.bottomRight, "vertical inner long edge", CGPoint(x: 880, y: 225)),
            (.bottomRight, "overlap", CGPoint(x: 880, y: 220))
        ]

        for fixture in fixtures {
            XCTAssertTrue(
                HotCornerGeometry.contains(point: fixture.point, frame: frame, corner: fixture.corner),
                "Expected \(fixture.label) to be included for \(fixture.corner)"
            )
        }
    }

    func testContainsExcludesPointsOutsideEachBoundaryByZeroPointOneForEveryCorner() {
        let frame = CGRect(x: -100, y: 200, width: 1000, height: 800)
        let fixtures: [(corner: TriggerCorner, label: String, point: CGPoint)] = [
            (.topLeft, "physical corner", CGPoint(x: -100.1, y: 1000.1)),
            (.topLeft, "horizontal far end", CGPoint(x: -13.9, y: 1000)),
            (.topLeft, "horizontal inner long edge", CGPoint(x: -75, y: 979.9)),
            (.topLeft, "vertical far end", CGPoint(x: -100, y: 913.9)),
            (.topLeft, "vertical inner long edge", CGPoint(x: -79.9, y: 975)),
            (.topLeft, "overlap", CGPoint(x: -79.9, y: 979.9)),
            (.topRight, "physical corner", CGPoint(x: 900.1, y: 1000.1)),
            (.topRight, "horizontal far end", CGPoint(x: 813.9, y: 1000)),
            (.topRight, "horizontal inner long edge", CGPoint(x: 875, y: 979.9)),
            (.topRight, "vertical far end", CGPoint(x: 900, y: 913.9)),
            (.topRight, "vertical inner long edge", CGPoint(x: 879.9, y: 975)),
            (.topRight, "overlap", CGPoint(x: 879.9, y: 979.9)),
            (.bottomLeft, "physical corner", CGPoint(x: -100.1, y: 199.9)),
            (.bottomLeft, "horizontal far end", CGPoint(x: -13.9, y: 200)),
            (.bottomLeft, "horizontal inner long edge", CGPoint(x: -75, y: 220.1)),
            (.bottomLeft, "vertical far end", CGPoint(x: -100, y: 286.1)),
            (.bottomLeft, "vertical inner long edge", CGPoint(x: -79.9, y: 225)),
            (.bottomLeft, "overlap", CGPoint(x: -79.9, y: 220.1)),
            (.bottomRight, "physical corner", CGPoint(x: 900.1, y: 199.9)),
            (.bottomRight, "horizontal far end", CGPoint(x: 813.9, y: 200)),
            (.bottomRight, "horizontal inner long edge", CGPoint(x: 875, y: 220.1)),
            (.bottomRight, "vertical far end", CGPoint(x: 900, y: 286.1)),
            (.bottomRight, "vertical inner long edge", CGPoint(x: 879.9, y: 225)),
            (.bottomRight, "overlap", CGPoint(x: 879.9, y: 220.1))
        ]

        for fixture in fixtures {
            XCTAssertFalse(
                HotCornerGeometry.contains(point: fixture.point, frame: frame, corner: fixture.corner),
                "Expected \(fixture.label) outside point to be excluded for \(fixture.corner)"
            )
        }
    }
}

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
                    CGRect(x: -100, y: 994, width: 43, height: 6),
                    CGRect(x: -100, y: 957, width: 6, height: 43)
                ],
                CGRect(x: -100, y: 994, width: 6, height: 6)
            ),
            (
                .topRight,
                [
                    CGRect(x: 857, y: 994, width: 43, height: 6),
                    CGRect(x: 894, y: 957, width: 6, height: 43)
                ],
                CGRect(x: 894, y: 994, width: 6, height: 6)
            ),
            (
                .bottomLeft,
                [
                    CGRect(x: -100, y: 200, width: 43, height: 6),
                    CGRect(x: -100, y: 200, width: 6, height: 43)
                ],
                CGRect(x: -100, y: 200, width: 6, height: 6)
            ),
            (
                .bottomRight,
                [
                    CGRect(x: 857, y: 200, width: 43, height: 6),
                    CGRect(x: 894, y: 200, width: 6, height: 43)
                ],
                CGRect(x: 894, y: 200, width: 6, height: 6)
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
            (.topLeft, "horizontal far end", CGPoint(x: -57, y: 1000)),
            (.topLeft, "horizontal inner long edge", CGPoint(x: -75, y: 994)),
            (.topLeft, "vertical far end", CGPoint(x: -100, y: 957)),
            (.topLeft, "vertical inner long edge", CGPoint(x: -94, y: 975)),
            (.topLeft, "overlap", CGPoint(x: -94, y: 994)),
            (.topRight, "physical corner", CGPoint(x: 900, y: 1000)),
            (.topRight, "horizontal far end", CGPoint(x: 857, y: 1000)),
            (.topRight, "horizontal inner long edge", CGPoint(x: 875, y: 994)),
            (.topRight, "vertical far end", CGPoint(x: 900, y: 957)),
            (.topRight, "vertical inner long edge", CGPoint(x: 894, y: 975)),
            (.topRight, "overlap", CGPoint(x: 894, y: 994)),
            (.bottomLeft, "physical corner", CGPoint(x: -100, y: 200)),
            (.bottomLeft, "horizontal far end", CGPoint(x: -57, y: 200)),
            (.bottomLeft, "horizontal inner long edge", CGPoint(x: -75, y: 206)),
            (.bottomLeft, "vertical far end", CGPoint(x: -100, y: 243)),
            (.bottomLeft, "vertical inner long edge", CGPoint(x: -94, y: 225)),
            (.bottomLeft, "overlap", CGPoint(x: -94, y: 206)),
            (.bottomRight, "physical corner", CGPoint(x: 900, y: 200)),
            (.bottomRight, "horizontal far end", CGPoint(x: 857, y: 200)),
            (.bottomRight, "horizontal inner long edge", CGPoint(x: 875, y: 206)),
            (.bottomRight, "vertical far end", CGPoint(x: 900, y: 243)),
            (.bottomRight, "vertical inner long edge", CGPoint(x: 894, y: 225)),
            (.bottomRight, "overlap", CGPoint(x: 894, y: 206))
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
            (.topLeft, "horizontal far end", CGPoint(x: -56.9, y: 1000)),
            (.topLeft, "horizontal inner long edge", CGPoint(x: -75, y: 993.9)),
            (.topLeft, "vertical far end", CGPoint(x: -100, y: 956.9)),
            (.topLeft, "vertical inner long edge", CGPoint(x: -93.9, y: 975)),
            (.topLeft, "overlap", CGPoint(x: -93.9, y: 993.9)),
            (.topRight, "physical corner", CGPoint(x: 900.1, y: 1000.1)),
            (.topRight, "horizontal far end", CGPoint(x: 856.9, y: 1000)),
            (.topRight, "horizontal inner long edge", CGPoint(x: 875, y: 993.9)),
            (.topRight, "vertical far end", CGPoint(x: 900, y: 956.9)),
            (.topRight, "vertical inner long edge", CGPoint(x: 893.9, y: 975)),
            (.topRight, "overlap", CGPoint(x: 893.9, y: 993.9)),
            (.bottomLeft, "physical corner", CGPoint(x: -100.1, y: 199.9)),
            (.bottomLeft, "horizontal far end", CGPoint(x: -56.9, y: 200)),
            (.bottomLeft, "horizontal inner long edge", CGPoint(x: -75, y: 206.1)),
            (.bottomLeft, "vertical far end", CGPoint(x: -100, y: 243.1)),
            (.bottomLeft, "vertical inner long edge", CGPoint(x: -93.9, y: 225)),
            (.bottomLeft, "overlap", CGPoint(x: -93.9, y: 206.1)),
            (.bottomRight, "physical corner", CGPoint(x: 900.1, y: 199.9)),
            (.bottomRight, "horizontal far end", CGPoint(x: 856.9, y: 200)),
            (.bottomRight, "horizontal inner long edge", CGPoint(x: 875, y: 206.1)),
            (.bottomRight, "vertical far end", CGPoint(x: 900, y: 243.1)),
            (.bottomRight, "vertical inner long edge", CGPoint(x: 893.9, y: 225)),
            (.bottomRight, "overlap", CGPoint(x: 893.9, y: 206.1))
        ]

        for fixture in fixtures {
            XCTAssertFalse(
                HotCornerGeometry.contains(point: fixture.point, frame: frame, corner: fixture.corner),
                "Expected \(fixture.label) outside point to be excluded for \(fixture.corner)"
            )
        }
    }
}

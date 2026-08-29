import XCTest

@testable import CornerPet

@MainActor
final class ReminderAnimationPolicyTests: XCTestCase {
    func testReducedMotionUsesPanelBaselineWithOpacityOnly() {
        for corner in TriggerCorner.allCases {
            let profile = ReminderAnimationPolicy.profile(
                reduceMotion: true,
                corner: corner
            )

            XCTAssertEqual(profile.duration, PanelAnimator.reducedMotionDuration)
            XCTAssertEqual(profile.initialScale, 1)
            XCTAssertEqual(profile.initialYOffset, 0)
            XCTAssertNil(profile.springBounce)
        }
    }

    func testNormalMotionRetainsExistingSpringAndCornerOffset() {
        XCTAssertEqual(
            ReminderAnimationPolicy.profile(reduceMotion: false, corner: .topLeft),
            ReminderAnimationProfile(
                duration: 0.42,
                initialScale: 0.9,
                initialYOffset: -10,
                springBounce: 0.3
            )
        )
        XCTAssertEqual(
            ReminderAnimationPolicy.profile(reduceMotion: false, corner: .bottomRight),
            ReminderAnimationProfile(
                duration: 0.42,
                initialScale: 0.9,
                initialYOffset: 10,
                springBounce: 0.3
            )
        )
    }
}

import CoreGraphics
import Foundation

struct ReminderAnimationProfile: Equatable, Sendable {
    let duration: TimeInterval
    let initialScale: CGFloat
    let initialYOffset: CGFloat
    let springBounce: Double?
}

@MainActor
enum ReminderAnimationPolicy {
    static func profile(
        reduceMotion: Bool,
        corner: TriggerCorner
    ) -> ReminderAnimationProfile {
        if reduceMotion {
            return ReminderAnimationProfile(
                duration: PanelAnimator.reducedMotionDuration,
                initialScale: 1,
                initialYOffset: 0,
                springBounce: nil
            )
        }

        let initialYOffset: CGFloat = switch corner {
        case .topLeft, .topRight: -10
        case .bottomLeft, .bottomRight: 10
        }
        return ReminderAnimationProfile(
            duration: 0.42,
            initialScale: 0.9,
            initialYOffset: initialYOffset,
            springBounce: 0.3
        )
    }
}

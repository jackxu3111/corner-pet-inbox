import CoreGraphics
import Darwin
import Foundation

enum PanelAnimationDirection: Equatable {
    case opening
    case closing
    case returning
}

struct PanelAnimationSample: Equatable {
    let progress: CGFloat
    let frame: CGRect
    let shellScale: CGFloat
    let windowAlpha: CGFloat
    let contentAlpha: CGFloat
    let isComplete: Bool
}

@MainActor
final class PanelAnimator {
    static let standardOpeningDuration: TimeInterval = 0.260
    static let standardClosingDuration: TimeInterval = 0.180
    static let reducedMotionDuration: TimeInterval = 0.120
    static let capsuleSize = CGSize(width: 44, height: 28)

    private let finalFrame: CGRect
    private let corner: TriggerCorner
    private let reducedMotion: Bool
    private let clock: () -> TimeInterval
    private var returnStartFrame: CGRect? = nil
    private var returnTargetFrame: CGRect? = nil

    private(set) var progress: CGFloat = 0
    private(set) var direction: PanelAnimationDirection?
    private(set) var isComplete = false
    private(set) var isTickerRunning = false

    var onSample: ((PanelAnimationSample) -> Void)?
    var onComplete: ((PanelAnimationDirection) -> Void)?

    private var lastTime: TimeInterval?
    private var completionDelivered = false
    private var ticker: Timer?

    init(
        finalFrame: CGRect,
        corner: TriggerCorner,
        reducedMotion: Bool,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.finalFrame = finalFrame
        self.corner = corner
        self.reducedMotion = reducedMotion
        self.clock = clock
    }

    @discardableResult
    func startOpening(at time: TimeInterval) -> PanelAnimationSample {
        begin(.opening, at: time)
        return sample(at: time)
    }

    @discardableResult
    func startClosing(at time: TimeInterval) -> PanelAnimationSample {
        begin(.closing, at: time)
        return sample(at: time)
    }

    @discardableResult
    func startReturning(
        from startFrame: CGRect,
        to targetFrame: CGRect,
        at time: TimeInterval
    ) -> PanelAnimationSample {
        returnStartFrame = startFrame
        returnTargetFrame = targetFrame
        progress = 0
        begin(.returning, at: time)
        return sample(at: time)
    }

    @discardableResult
    func reverse(at time: TimeInterval) -> PanelAnimationSample {
        advance(to: time)
        let current = makeSample()

        guard !isComplete,
              time.isFinite,
              let direction,
              let currentLastTime = lastTime,
              time >= currentLastTime else {
            return current
        }

        switch direction {
        case .opening:
            self.direction = .closing
        case .closing:
            self.direction = .opening
        case .returning:
            return current
        }
        self.lastTime = time
        return current
    }

    @discardableResult
    func sample(at time: TimeInterval) -> PanelAnimationSample {
        advance(to: time)
        return makeSample()
    }

    func startTicker() {
        stopTicker()

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(handleTicker(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        isTickerRunning = true
    }

    func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        isTickerRunning = false
    }

    @discardableResult
    func tick(at time: TimeInterval? = nil) -> PanelAnimationSample {
        let sample = sample(at: time ?? clock())
        onSample?(sample)
        if sample.isComplete, isComplete {
            stopTicker()
        }
        return sample
    }

    @objc private func handleTicker(_ timer: Timer) {
        _ = tick()
    }

    private func begin(_ newDirection: PanelAnimationDirection, at time: TimeInterval) {
        direction = newDirection
        isComplete = false
        completionDelivered = false
        lastTime = time.isFinite ? time : nil
    }

    private func advance(to time: TimeInterval) {
        guard time.isFinite,
              let lastTime,
              time >= lastTime,
              let direction,
              !isComplete else {
            return
        }

        let delta = time - lastTime
        guard delta.isFinite else {
            return
        }
        self.lastTime = time

        let duration = reducedMotion
            ? Self.reducedMotionDuration
            : direction == .opening
                ? Self.standardOpeningDuration
                : Self.standardClosingDuration
        let change = CGFloat(delta / duration)

        switch direction {
        case .opening:
            progress = min(1, progress + change)
            if progress >= 1 {
                finish()
            }
        case .closing:
            progress = max(0, progress - change)
            if progress <= 0 {
                finish()
            }
        case .returning:
            progress = min(1, progress + change)
            if progress >= 1 {
                finish()
            }
        }
    }

    private func finish() {
        progress = min(1, max(0, progress))
        isComplete = true

        guard !completionDelivered, let direction else {
            return
        }
        completionDelivered = true
        onComplete?(direction)
    }

    private func makeSample() -> PanelAnimationSample {
        if direction == .returning,
           let returnStartFrame,
           let returnTargetFrame {
            return PanelAnimationSample(
                progress: progress,
                frame: interpolatedFrame(
                    from: returnStartFrame,
                    to: returnTargetFrame,
                    progress: progress
                ),
                shellScale: 1,
                windowAlpha: 1,
                contentAlpha: 1,
                isComplete: isComplete
            )
        }

        let shellScale: CGFloat
        let windowAlpha: CGFloat
        let contentAlpha: CGFloat

        if reducedMotion {
            shellScale = 0.96 + (0.04 * progress)
            windowAlpha = smoothstep(progress)
            contentAlpha = windowAlpha
        } else {
            shellScale = normalizedGrowth(progress)
            windowAlpha = 1
            let contentProgress = min(1, max(0, (progress - 0.22) / 0.50))
            contentAlpha = smoothstep(contentProgress)
        }

        return PanelAnimationSample(
            progress: progress,
            frame: anchoredFrame(scale: shellScale),
            shellScale: shellScale,
            windowAlpha: windowAlpha,
            contentAlpha: contentAlpha,
            isComplete: isComplete
        )
    }

    private func interpolatedFrame(
        from start: CGRect,
        to target: CGRect,
        progress: CGFloat
    ) -> CGRect {
        let eased = reducedMotion ? progress : normalizedGrowth(progress)
        return CGRect(
            x: start.minX + (target.minX - start.minX) * eased,
            y: start.minY + (target.minY - start.minY) * eased,
            width: start.width + (target.width - start.width) * eased,
            height: start.height + (target.height - start.height) * eased
        )
    }

    private func normalizedGrowth(_ progress: CGFloat) -> CGFloat {
        let denominator = 1.0 - Darwin.exp(-14.0) * Darwin.cos(10.0)
        let numerator = 1.0
            - Darwin.exp(-14.0 * Double(progress)) * Darwin.cos(10.0 * Double(progress))
        return CGFloat(numerator / denominator)
    }

    private func anchoredFrame(scale: CGFloat) -> CGRect {
        let capsule = Self.capsuleSize
        let size = CGSize(
            width: capsule.width + (finalFrame.width - capsule.width) * scale,
            height: capsule.height + (finalFrame.height - capsule.height) * scale
        )

        switch corner {
        case .topLeft:
            return CGRect(
                x: finalFrame.minX,
                y: finalFrame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .topRight:
            return CGRect(
                x: finalFrame.maxX - size.width,
                y: finalFrame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .bottomLeft:
            return CGRect(
                x: finalFrame.minX,
                y: finalFrame.minY,
                width: size.width,
                height: size.height
            )
        case .bottomRight:
            return CGRect(
                x: finalFrame.maxX - size.width,
                y: finalFrame.minY,
                width: size.width,
                height: size.height
            )
        }
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - (2 * value))
    }
}

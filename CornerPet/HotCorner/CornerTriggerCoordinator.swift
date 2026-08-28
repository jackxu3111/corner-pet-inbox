import AppKit
import Foundation

typealias HotCornerClock = @MainActor () -> TimeInterval
typealias PointerLocationProvider = @MainActor () -> CGPoint

protocol HotCornerCancellation: AnyObject {
    @MainActor
    func cancel()
}

protocol HotCornerDeadlineScheduling: AnyObject {
    @MainActor
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> HotCornerCancellation
}

typealias PanelDeadlineScheduling = HotCornerDeadlineScheduling

@MainActor
final class MainRunLoopDeadlineScheduler: HotCornerDeadlineScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> HotCornerCancellation {
        MainRunLoopDeadlineCancellation(delay: delay, operation: operation)
    }
}

@MainActor
private final class MainRunLoopDeadlineCancellation: HotCornerCancellation {
    private var timer: Timer?

    init(delay: TimeInterval, operation: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { _ in
            Task { @MainActor in
                operation()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class CornerTriggerCoordinator {
    private struct PendingDwell {
        let deadline: HotCornerDeadline
        let cancellation: HotCornerCancellation
    }

    private let screenProvider: () -> NSScreen?
    private let clock: HotCornerClock
    private let pointerLocationProvider: PointerLocationProvider
    private let scheduler: HotCornerDeadlineScheduling
    private let defaultPresentPanel: (UInt32) -> Void
    private let defaultReverseClosingPanel: (UInt32) -> Void
    private let dwellDuration: TimeInterval

    private var stateMachine: HotCornerStateMachine
    private(set) var corner: TriggerCorner
    private var screenFrame: CGRect?
    private var screenID: UInt32?
    private var pendingDwell: PendingDwell?

    private(set) var horizontalPanel: TriggerZonePanel?
    private(set) var verticalPanel: TriggerZonePanel?
    private(set) var isRunning = false
    private(set) var isInsideTrigger = false

    var onPresentRequested: ((UInt32) -> Void)?
    var onReverseClosingRequested: ((UInt32) -> Void)?
    var onTriggerPresenceChanged: ((Bool) -> Void)?

    init(
        screenProvider: @escaping () -> NSScreen?,
        corner: TriggerCorner = .topLeft,
        clock: @escaping HotCornerClock = { ProcessInfo.processInfo.systemUptime },
        pointerLocationProvider: @escaping PointerLocationProvider = { NSEvent.mouseLocation },
        scheduler: HotCornerDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        presentPanel: @escaping (UInt32) -> Void,
        reverseClosingPanel: @escaping (UInt32) -> Void,
        dwellDuration: TimeInterval = DwellTiming.duration
    ) {
        self.screenProvider = screenProvider
        self.corner = corner
        self.clock = clock
        self.pointerLocationProvider = pointerLocationProvider
        self.scheduler = scheduler
        defaultPresentPanel = presentPanel
        defaultReverseClosingPanel = reverseClosingPanel
        self.dwellDuration = dwellDuration
        stateMachine = HotCornerStateMachine(dwellDuration: dwellDuration)
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard let screen = screenProvider(),
              let displayID = Self.displayID(for: screen) else {
            return false
        }

        let frames = TriggerZonePanel.frames(for: screen.frame, corner: corner)
        screenFrame = screen.frame
        screenID = displayID
        horizontalPanel = TriggerZonePanel(frame: frames.horizontal) { [weak self] in
            self?.refreshPresence()
        }
        verticalPanel = TriggerZonePanel(frame: frames.vertical) { [weak self] in
            self?.refreshPresence()
        }

        isRunning = true
        horizontalPanel?.orderFrontRegardless()
        verticalPanel?.orderFrontRegardless()
        refreshPresence()
        return true
    }

    func stop() {
        guard isRunning || horizontalPanel != nil || verticalPanel != nil else { return }
        pendingDwell?.cancellation.cancel()
        pendingDwell = nil
        horizontalPanel?.orderOut(nil)
        verticalPanel?.orderOut(nil)
        horizontalPanel = nil
        verticalPanel = nil
        screenFrame = nil
        screenID = nil
        isInsideTrigger = false
        stateMachine = HotCornerStateMachine(dwellDuration: dwellDuration)
        isRunning = false
    }

    func updateCorner(_ corner: TriggerCorner) {
        guard self.corner != corner else { return }

        pendingDwell?.cancellation.cancel()
        pendingDwell = nil
        for effect in stateMachine.handle(.presenceChanged(
            HotCornerPointerPresence(isInsideTrigger: false, isInsidePanel: false),
            at: clock()
        )) {
            apply(effect)
        }
        self.corner = corner
        isInsideTrigger = false
        onTriggerPresenceChanged?(false)

        guard isRunning, let screenFrame else { return }
        let frames = TriggerZonePanel.frames(for: screenFrame, corner: corner)
        horizontalPanel?.setFrame(frames.horizontal, display: true)
        verticalPanel?.setFrame(frames.vertical, display: true)
        refreshPresence()
    }

    func refreshPresence() {
        guard isRunning else { return }
        let point = pointerLocationProvider()
        let inside = screenFrame.map { frame in
            HotCornerGeometry.contains(point: point, frame: frame, corner: corner)
        } ?? false
        isInsideTrigger = inside
        handle(.presenceChanged(
            HotCornerPointerPresence(isInsideTrigger: inside, isInsidePanel: false),
            at: clock()
        ))
        onTriggerPresenceChanged?(inside)
    }

    func panelBeganOpening() {
        handle(.panelBeganOpening(at: clock()))
    }

    func panelDidOpen() {
        handle(.panelDidOpen(at: clock()))
    }

    func panelBeganClosing() {
        handle(.panelBeganClosing(at: clock()))
    }

    func panelDidClose() {
        handle(.panelDidClose(at: clock()))
        refreshPresence()
    }

    func escapePressed() {
        handle(.escapePressed(at: clock()))
    }

    private func handle(_ event: HotCornerEvent) {
        guard isRunning else { return }
        for effect in stateMachine.handle(event) {
            apply(effect)
        }
    }

    private func apply(_ effect: HotCornerEffect) {
        switch effect {
        case let .schedule(deadline):
            schedule(deadline)
        case .cancelDeadline:
            pendingDwell?.cancellation.cancel()
            pendingDwell = nil
        case .present:
            guard let screenID else { return }
            (onPresentRequested ?? defaultPresentPanel)(screenID)
        case .reverseClosing:
            guard let screenID else { return }
            (onReverseClosingRequested ?? defaultReverseClosingPanel)(screenID)
        }
    }

    private func schedule(_ deadline: HotCornerDeadline) {
        pendingDwell?.cancellation.cancel()
        pendingDwell = nil

        let now = clock()
        guard now.isFinite else { return }
        let delay = deadline.dueAt - now
        guard delay.isFinite, delay >= 0 else { return }

        let cancellation = scheduler.schedule(after: delay) { [weak self] in
            self?.fire(deadline)
        }
        pendingDwell = PendingDwell(deadline: deadline, cancellation: cancellation)
    }

    private func fire(_ deadline: HotCornerDeadline) {
        guard isRunning,
              pendingDwell?.deadline == deadline else {
            return
        }

        pendingDwell = nil
        let now = clock()
        guard now.isFinite else { return }
        guard now >= deadline.dueAt else {
            schedule(deadline)
            return
        }

        let point = pointerLocationProvider()
        let inside = screenFrame.map { frame in
            HotCornerGeometry.contains(point: point, frame: frame, corner: corner)
        } ?? false
        isInsideTrigger = inside
        handle(.deadlineReached(
            deadline,
            presence: HotCornerPointerPresence(isInsideTrigger: inside, isInsidePanel: false),
            at: now
        ))
        onTriggerPresenceChanged?(inside)
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

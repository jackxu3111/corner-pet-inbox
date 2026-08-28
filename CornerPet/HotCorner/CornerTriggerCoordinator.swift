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

    private struct PendingPinnedDwell {
        let screenID: UInt32
        let dueAt: TimeInterval
        let cancellation: HotCornerCancellation
    }

    private struct TriggerZonePair {
        let horizontal: TriggerZonePanel
        let vertical: TriggerZonePanel
    }

    private let screenSnapshotsProvider: () -> [ScreenSnapshot]
    private let clock: HotCornerClock
    private let pointerLocationProvider: PointerLocationProvider
    private let scheduler: HotCornerDeadlineScheduling
    private let defaultPresentPanel: (UInt32) -> Void
    private let defaultReverseClosingPanel: (UInt32) -> Void
    private let isPanelPinned: () -> Bool
    private let bringPinnedPanelForward: () -> Void
    private let dwellDuration: TimeInterval

    private var stateMachine: HotCornerStateMachine
    private(set) var corner: TriggerCorner
    private var enabledScreens: [ScreenSnapshot] = []
    private var triggerZones: [UInt32: TriggerZonePair] = [:]
    private var activeScreenID: UInt32?
    private var pendingDwell: PendingDwell?
    private var pendingPinnedDwell: PendingPinnedDwell?
    private var pinnedRetriggerRequiresExit = false

    var horizontalPanel: TriggerZonePanel? {
        enabledScreens.first.flatMap { triggerZones[$0.id]?.horizontal }
    }

    var verticalPanel: TriggerZonePanel? {
        enabledScreens.first.flatMap { triggerZones[$0.id]?.vertical }
    }

    var triggerScreenIDs: [UInt32] {
        enabledScreens.map(\.id)
    }

    var triggerPanelFrames: [UInt32: TriggerZonePanel.ArmFrames] {
        enabledScreens.reduce(into: [:]) { result, screen in
            guard let pair = triggerZones[screen.id] else { return }
            result[screen.id] = TriggerZonePanel.ArmFrames(
                horizontal: pair.horizontal.frame,
                vertical: pair.vertical.frame
            )
        }
    }

    private(set) var isRunning = false
    private(set) var isInsideTrigger = false

    var onPresentRequested: ((UInt32) -> Void)?
    var onReverseClosingRequested: ((UInt32) -> Void)?
    var onTriggerPresenceChanged: ((Bool) -> Void)?

    convenience init(
        screenProvider: @escaping () -> NSScreen?,
        corner: TriggerCorner = .topLeft,
        clock: @escaping HotCornerClock = { ProcessInfo.processInfo.systemUptime },
        pointerLocationProvider: @escaping PointerLocationProvider = { NSEvent.mouseLocation },
        scheduler: HotCornerDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        presentPanel: @escaping (UInt32) -> Void,
        reverseClosingPanel: @escaping (UInt32) -> Void,
        isPanelPinned: @escaping () -> Bool = { false },
        bringPinnedPanelForward: @escaping () -> Void = {},
        dwellDuration: TimeInterval = DwellTiming.duration
    ) {
        self.init(
            screenSnapshotsProvider: {
                screenProvider().flatMap(Self.snapshot(for:)).map { [$0] } ?? []
            },
            corner: corner,
            clock: clock,
            pointerLocationProvider: pointerLocationProvider,
            scheduler: scheduler,
            presentPanel: presentPanel,
            reverseClosingPanel: reverseClosingPanel,
            isPanelPinned: isPanelPinned,
            bringPinnedPanelForward: bringPinnedPanelForward,
            dwellDuration: dwellDuration
        )
    }

    init(
        screenSnapshotsProvider: @escaping () -> [ScreenSnapshot],
        corner: TriggerCorner = .topLeft,
        clock: @escaping HotCornerClock = { ProcessInfo.processInfo.systemUptime },
        pointerLocationProvider: @escaping PointerLocationProvider = { NSEvent.mouseLocation },
        scheduler: HotCornerDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        presentPanel: @escaping (UInt32) -> Void,
        reverseClosingPanel: @escaping (UInt32) -> Void,
        isPanelPinned: @escaping () -> Bool = { false },
        bringPinnedPanelForward: @escaping () -> Void = {},
        dwellDuration: TimeInterval = DwellTiming.duration
    ) {
        self.screenSnapshotsProvider = screenSnapshotsProvider
        self.corner = corner
        self.clock = clock
        self.pointerLocationProvider = pointerLocationProvider
        self.scheduler = scheduler
        defaultPresentPanel = presentPanel
        defaultReverseClosingPanel = reverseClosingPanel
        self.isPanelPinned = isPanelPinned
        self.bringPinnedPanelForward = bringPinnedPanelForward
        self.dwellDuration = dwellDuration
        stateMachine = HotCornerStateMachine(dwellDuration: dwellDuration)
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let screens = enabledScreens.isEmpty ? screenSnapshotsProvider() : enabledScreens
        guard !screens.isEmpty else {
            return false
        }

        enabledScreens = screens
        isRunning = true
        rebuildTriggerZones()
        refreshPresence()
        return true
    }

    func stop() {
        guard isRunning || !triggerZones.isEmpty else { return }
        pendingDwell?.cancellation.cancel()
        pendingDwell = nil
        cancelPinnedDwell()
        pinnedRetriggerRequiresExit = false
        removeTriggerZones()
        enabledScreens = []
        activeScreenID = nil
        isInsideTrigger = false
        stateMachine = HotCornerStateMachine(dwellDuration: dwellDuration)
        isRunning = false
    }

    func updateCorner(_ corner: TriggerCorner) {
        guard self.corner != corner else { return }

        pendingDwell?.cancellation.cancel()
        pendingDwell = nil
        cancelPinnedDwell()
        pinnedRetriggerRequiresExit = false
        for effect in stateMachine.handle(.presenceChanged(
            HotCornerPointerPresence(isInsideTrigger: false, isInsidePanel: false),
            at: clock()
        )) {
            apply(effect)
        }
        self.corner = corner
        isInsideTrigger = false
        onTriggerPresenceChanged?(false)

        guard isRunning else { return }
        for screen in enabledScreens {
            let frames = TriggerZonePanel.frames(for: screen.frame, corner: corner)
            triggerZones[screen.id]?.horizontal.setFrame(frames.horizontal, display: true)
            triggerZones[screen.id]?.vertical.setFrame(frames.vertical, display: true)
        }
        refreshPresence()
    }

    func updateScreens(_ screens: [ScreenSnapshot]) {
        guard enabledScreens != screens else { return }
        resetPresenceForGeometryChange()
        enabledScreens = screens
        guard isRunning else { return }
        rebuildTriggerZones()
        refreshPresence()
    }

    func refreshPresence() {
        guard isRunning else { return }
        let point = pointerLocationProvider()
        let matchingScreen = triggerScreen(containing: point)
        let inside = matchingScreen != nil
        activeScreenID = matchingScreen?.id
        isInsideTrigger = inside
        handle(.presenceChanged(
            HotCornerPointerPresence(isInsideTrigger: inside, isInsidePanel: false),
            at: clock()
        ))
        refreshPinnedRetrigger(inside: inside, screenID: matchingScreen?.id)
        onTriggerPresenceChanged?(inside)
    }

    func panelBeganOpening() {
        handle(.panelBeganOpening(at: clock()))
    }

    func panelDidOpen() {
        handle(.panelDidOpen(at: clock()))
    }

    func panelBeganClosing() {
        cancelPinnedDwell()
        handle(.panelBeganClosing(at: clock()))
    }

    func panelDidClose() {
        cancelPinnedDwell()
        pinnedRetriggerRequiresExit = false
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
            guard let activeScreenID else { return }
            (onPresentRequested ?? defaultPresentPanel)(activeScreenID)
        case .reverseClosing:
            guard let activeScreenID else { return }
            (onReverseClosingRequested ?? defaultReverseClosingPanel)(activeScreenID)
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
        let matchingScreen = triggerScreen(containing: point)
        let inside = matchingScreen != nil
        activeScreenID = matchingScreen?.id
        isInsideTrigger = inside
        handle(.deadlineReached(
            deadline,
            presence: HotCornerPointerPresence(isInsideTrigger: inside, isInsidePanel: false),
            at: now
        ))
        refreshPinnedRetrigger(inside: inside, screenID: matchingScreen?.id)
        onTriggerPresenceChanged?(inside)
    }

    private func rebuildTriggerZones() {
        removeTriggerZones()
        for screen in enabledScreens {
            let frames = TriggerZonePanel.frames(for: screen.frame, corner: corner)
            let pair = TriggerZonePair(
                horizontal: TriggerZonePanel(frame: frames.horizontal) { [weak self] in
                    self?.refreshPresence()
                },
                vertical: TriggerZonePanel(frame: frames.vertical) { [weak self] in
                    self?.refreshPresence()
                }
            )
            triggerZones[screen.id] = pair
            pair.horizontal.orderFrontRegardless()
            pair.vertical.orderFrontRegardless()
        }
    }

    private func removeTriggerZones() {
        for pair in triggerZones.values {
            pair.horizontal.orderOut(nil)
            pair.vertical.orderOut(nil)
        }
        triggerZones.removeAll()
    }

    private func resetPresenceForGeometryChange() {
        pendingDwell?.cancellation.cancel()
        pendingDwell = nil
        cancelPinnedDwell()
        pinnedRetriggerRequiresExit = false
        for effect in stateMachine.handle(.presenceChanged(
            HotCornerPointerPresence(isInsideTrigger: false, isInsidePanel: false),
            at: clock()
        )) {
            apply(effect)
        }
        activeScreenID = nil
        isInsideTrigger = false
        onTriggerPresenceChanged?(false)
    }

    private func triggerScreen(containing point: CGPoint) -> ScreenSnapshot? {
        enabledScreens.first { screen in
            HotCornerGeometry.contains(point: point, frame: screen.frame, corner: corner)
        }
    }

    private func refreshPinnedRetrigger(inside: Bool, screenID: UInt32?) {
        guard isPanelPinned() else {
            cancelPinnedDwell()
            pinnedRetriggerRequiresExit = false
            return
        }
        guard inside, let screenID else {
            cancelPinnedDwell()
            pinnedRetriggerRequiresExit = false
            return
        }
        guard !pinnedRetriggerRequiresExit, pendingPinnedDwell == nil else { return }

        let now = clock()
        let dueAt = now + dwellDuration
        guard now.isFinite, dueAt.isFinite else { return }
        let cancellation = scheduler.schedule(after: dwellDuration) { [weak self] in
            self?.firePinnedDwell(screenID: screenID, dueAt: dueAt)
        }
        pendingPinnedDwell = PendingPinnedDwell(
            screenID: screenID,
            dueAt: dueAt,
            cancellation: cancellation
        )
    }

    private func firePinnedDwell(screenID: UInt32, dueAt: TimeInterval) {
        guard isRunning,
              let pendingPinnedDwell,
              pendingPinnedDwell.screenID == screenID,
              pendingPinnedDwell.dueAt == dueAt,
              isPanelPinned(),
              clock() >= dueAt else {
            return
        }
        self.pendingPinnedDwell = nil
        let point = pointerLocationProvider()
        guard triggerScreen(containing: point)?.id == screenID else { return }
        pinnedRetriggerRequiresExit = true
        bringPinnedPanelForward()
    }

    private func cancelPinnedDwell() {
        pendingPinnedDwell?.cancellation.cancel()
        pendingPinnedDwell = nil
    }

    private static func snapshot(for screen: NSScreen) -> ScreenSnapshot? {
        guard let id = (
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        )?.uint32Value else {
            return nil
        }
        return ScreenSnapshot(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}

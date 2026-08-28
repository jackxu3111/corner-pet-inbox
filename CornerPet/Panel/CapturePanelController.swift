import AppKit
import Foundation

enum CapturePanelLifecycleEvent: Equatable {
    case beganOpening(screenID: UInt32)
    case didOpen(screenID: UInt32)
    case beganClosing(screenID: UInt32)
    case didClose
}

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    typealias HostedContentFactory = @MainActor () -> NSView

    private enum Phase {
        case hidden
        case opening
        case open
        case returning
        case closing
    }

    private let screenProvider: (UInt32) -> NSScreen?
    private let screensProvider: () -> [PanelScreenGeometry]
    private let clock: () -> TimeInterval
    private let reducedMotionProvider: () -> Bool
    private let loadPinnedSize: () -> CGSize
    private let savePinnedSize: (CGSize) -> Void
    private var corner: TriggerCorner

    private var phase: Phase = .hidden
    private var closeWhenOpen = false
    private(set) var isPinned = false
    private(set) var currentScreenID: UInt32?
    private var animator: PanelAnimator?
    private var inputProbe: EscapeInputProbe?
    private var hostedContentFactory: HostedContentFactory?

    private(set) var panel: CornerPanel?

    var onLifecycle: ((CapturePanelLifecycleEvent) -> Void)?
    var onPointerBoundaryChanged: (() -> Void)?
    var onEscape: (() -> Void)?
    var onExternalFocusLost: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onReturnToCorner: (() -> Void)?
    var onCornerChanged: ((TriggerCorner) -> Void)?

    var isVisible: Bool {
        phase != .hidden
    }

    var keepOpenFrame: CGRect? {
        isVisible ? panel?.frame : nil
    }

    var animationDirection: PanelAnimationDirection? {
        animator?.direction
    }

    init(
        screenProvider: @escaping (UInt32) -> NSScreen?,
        screensProvider: @escaping () -> [PanelScreenGeometry] = {
            CapturePanelController.currentScreenGeometries()
        },
        corner: TriggerCorner = .topLeft,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        reducedMotionProvider: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        pinnedSizeStore: PinnedPanelSizeStore = PinnedPanelSizeStore(),
        loadPinnedSize: (() -> CGSize)? = nil,
        savePinnedSize: ((CGSize) -> Void)? = nil
    ) {
        self.screenProvider = screenProvider
        self.screensProvider = screensProvider
        self.corner = corner
        self.clock = clock
        self.reducedMotionProvider = reducedMotionProvider
        self.loadPinnedSize = loadPinnedSize ?? { pinnedSizeStore.load() }
        self.savePinnedSize = savePinnedSize ?? { pinnedSizeStore.save($0) }
        super.init()
    }

    func present(screenID: UInt32) {
        guard case .hidden = phase,
              let screen = screenProvider(screenID) else {
            return
        }

        let panelSize = loadPinnedSize()
        let finalFrame = PanelPositioner.frame(
            inside: screen.visibleFrame,
            corner: corner,
            size: panelSize
        )

        let panel = self.panel ?? CornerPanel(contentRect: finalFrame)
        panel.onTogglePin = { [weak self] in
            self?.togglePin()
        }
        panel.delegate = self
        panel.setPinned(false)
        let inputProbe = EscapeInputProbe(owner: self)
        if let hostedContentFactory {
            inputProbe.installHostedContent(hostedContentFactory())
        }
        panel.contentView = inputProbe
        panel.setFrame(finalFrame, display: false)
        panel.ignoresMouseEvents = true
        panel.alphaValue = 1

        let animator = makeAnimator(finalFrame: finalFrame, corner: corner)

        self.panel = panel
        self.inputProbe = inputProbe
        self.animator = animator
        self.currentScreenID = screenID
        phase = .opening
        isPinned = false
        closeWhenOpen = false

        let initialSample = animator.startOpening(at: clock())
        apply(initialSample)
        emit(.beganOpening(screenID: screenID))

        panel.orderFront(nil)
        panel.makeKeyAndOrderFront(nil)
        animator.startTicker()
    }

    func installHostedContentFactory(_ factory: @escaping HostedContentFactory) {
        hostedContentFactory = factory
        inputProbe?.installHostedContent(factory())
    }

    func handleCaptureCommand(_ command: CapturePanelCommand) {
        switch command {
        case .focusInputAtEnd:
            break
        case .close(.escape):
            handleEscape()
        case .close(.submittedOutside):
            dismiss()
        }
    }

    func togglePin() {
        onTogglePin?()
    }

    func setPinned(_ pinned: Bool) {
        guard let panel, isVisible else { return }
        panel.setPinned(pinned)
        isPinned = pinned
    }

    func bringForward() {
        guard isPinned, isVisible, let panel else { return }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func updateCorner(_ corner: TriggerCorner) {
        guard self.corner != corner else { return }
        self.corner = corner
        guard case .open = phase,
              !isPinned,
              let currentScreenID,
              let screen = screenProvider(currentScreenID),
              let panel else {
            return
        }
        panel.setFrame(
            PanelPositioner.frame(
                inside: screen.visibleFrame,
                corner: corner,
                size: panel.frame.size
            ),
            display: true
        )
        onPointerBoundaryChanged?()
    }

    func handleScreenConfigurationChange(_ configuration: ScreenConfiguration) {
        guard isVisible, let panel else { return }
        let current = currentScreenID.flatMap { currentID in
            configuration.allScreens.first { $0.id == currentID }
        }
        guard let target = current ?? configuration.primaryScreen ?? configuration.allScreens.first else {
            return
        }

        let targetSize = if case .opening = phase {
            loadPinnedSize()
        } else {
            panel.frame.size
        }
        let targetFrame = if isPinned {
            PanelPositioner.clampedFrame(panel.frame, inside: target.visibleFrame)
        } else {
            PanelPositioner.frame(
                inside: target.visibleFrame,
                corner: corner,
                size: targetSize
            )
        }

        animator?.stopTicker()
        currentScreenID = target.id

        switch phase {
        case .opening:
            let replacement = makeAnimator(finalFrame: targetFrame, corner: corner)
            animator = replacement
            apply(replacement.startOpening(at: clock()))
            replacement.startTicker()
        case .returning:
            let replacement = makeAnimator(finalFrame: targetFrame, corner: corner)
            animator = replacement
            apply(replacement.startReturning(
                from: panel.frame,
                to: targetFrame,
                at: clock()
            ))
            replacement.startTicker()
        case .open:
            animator = makeCompletedOpeningAnimator(
                finalFrame: targetFrame,
                corner: corner
            )
            panel.setFrame(targetFrame, display: true)
        case .closing:
            finishClosing()
        case .hidden:
            break
        }
        onPointerBoundaryChanged?()
    }

    func dismiss() {
        switch phase {
        case .opening:
            closeWhenOpen = true
        case .open:
            beginClosing()
        case .returning:
            closeWhenOpen = true
        case .hidden, .closing:
            break
        }
    }

    func returnToCorner() {
        guard case .open = phase,
              !isPinned,
              let panel else {
            return
        }

        let retainedSize = PinnedPanelSizeStore.clamped(panel.frame.size)
        var panelFrame = panel.frame
        panelFrame.size = retainedSize
        guard let target = PanelPositioner.returnTarget(
            for: panelFrame,
            screens: screensProvider(),
            currentScreenID: currentScreenID,
            currentCorner: corner
        ) else {
            return
        }

        let previousCorner = corner
        corner = target.corner
        currentScreenID = target.screenID
        if previousCorner != corner {
            onCornerChanged?(corner)
        }

        let targetFrame = target.frame
        guard panel.frame != targetFrame else {
            onReturnToCorner?()
            onPointerBoundaryChanged?()
            return
        }

        let animator = makeAnimator(finalFrame: targetFrame, corner: target.corner)

        self.animator = animator
        phase = .returning
        panel.ignoresMouseEvents = true
        let initialSample = animator.startReturning(
            from: panel.frame,
            to: targetFrame,
            at: clock()
        )
        apply(initialSample)
        animator.startTicker()
    }

    func reverseClosing(screenID: UInt32) {
        guard currentScreenID == screenID else {
            return
        }

        switch phase {
        case .opening:
            guard closeWhenOpen else {
                return
            }
            closeWhenOpen = false
            emit(.beganOpening(screenID: screenID))

        case .closing:
            guard let animator else {
                return
            }

            let sample = animator.reverse(at: clock())
            guard !sample.isComplete, animator.direction == .opening else {
                return
            }

            phase = .opening
            apply(sample)
            emit(.beganOpening(screenID: screenID))
            animator.startTicker()

        case .returning:
            closeWhenOpen = false

        case .hidden, .open:
            return
        }
    }

    func reverseClosing() {
        guard let currentScreenID else { return }
        reverseClosing(screenID: currentScreenID)
    }

    @discardableResult
    func tick(at time: TimeInterval) -> PanelAnimationSample? {
        animator?.tick(at: time)
    }

    private func beginClosing() {
        guard case .open = phase,
              let screenID = currentScreenID,
              let panel,
              let animator else {
            return
        }

        phase = .closing
        panel.ignoresMouseEvents = true

        let initialSample = animator.startClosing(at: clock())
        apply(initialSample)
        emit(.beganClosing(screenID: screenID))
        animator.startTicker()
    }

    private func makeAnimator(finalFrame: CGRect, corner: TriggerCorner) -> PanelAnimator {
        let animator = PanelAnimator(
            finalFrame: finalFrame,
            corner: corner,
            reducedMotion: reducedMotionProvider(),
            clock: clock
        )
        animator.onSample = { [weak self, weak animator] sample in
            guard let self, self.animator === animator else { return }
            self.consume(sample)
        }
        return animator
    }

    private func makeCompletedOpeningAnimator(
        finalFrame: CGRect,
        corner: TriggerCorner
    ) -> PanelAnimator {
        let animator = makeAnimator(finalFrame: finalFrame, corner: corner)
        let startTime = clock()
        _ = animator.startOpening(at: startTime)
        _ = animator.sample(at: startTime + PanelAnimator.standardOpeningDuration)
        return animator
    }

    private func consume(_ sample: PanelAnimationSample) {
        apply(sample)

        guard sample.isComplete,
              let direction = animator?.direction else {
            return
        }

        switch (phase, direction) {
        case (.opening, .opening):
            finishOpening()
        case (.returning, .returning):
            finishReturning()
        case (.closing, .closing):
            finishClosing()
        default:
            break
        }
    }

    private func apply(_ sample: PanelAnimationSample) {
        panel?.setFrame(sample.frame, display: true)
        panel?.alphaValue = sample.windowAlpha
        panel?.contentView?.alphaValue = sample.contentAlpha
    }

    private func finishOpening() {
        guard case .opening = phase,
              let screenID = currentScreenID,
              let panel else {
            return
        }

        animator?.stopTicker()
        panel.ignoresMouseEvents = false
        if let inputProbe {
            panel.makeFirstResponder(inputProbe)
        }
        phase = .open
        emit(.didOpen(screenID: screenID))

        if closeWhenOpen {
            closeWhenOpen = false
            beginClosing()
        }
    }

    private func finishClosing() {
        guard case .closing = phase,
              let panel else {
            return
        }

        animator?.stopTicker()
        panel.ignoresMouseEvents = true
        panel.setPinned(false)
        isPinned = false
        panel.orderOut(nil)
        phase = .hidden
        currentScreenID = nil
        closeWhenOpen = false
        animator = nil
        emit(.didClose)
    }

    private func finishReturning() {
        guard case .returning = phase,
              let panel else {
            return
        }

        animator?.stopTicker()
        panel.ignoresMouseEvents = false
        phase = .open
        onReturnToCorner?()
        onPointerBoundaryChanged?()
        if closeWhenOpen {
            closeWhenOpen = false
            beginClosing()
        }
    }

    fileprivate func notifyPointerBoundaryChanged() {
        onPointerBoundaryChanged?()
    }

    fileprivate func handleEscape() {
        onEscape?()
        dismiss()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard case .open = phase else { return }
        onExternalFocusLost?()
    }

    func windowDidEndLiveResize() {
        guard isPinned, let panel else { return }
        let clampedSize = PinnedPanelSizeStore.clamped(panel.contentSize)
        if panel.contentSize != clampedSize {
            panel.setContentSize(clampedSize)
        }
        savePinnedSize(clampedSize)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        windowDidEndLiveResize()
    }

    private func emit(_ event: CapturePanelLifecycleEvent) {
        onLifecycle?(event)
        onPointerBoundaryChanged?()
    }

    private static func currentScreenGeometries() -> [PanelScreenGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let id = (
                screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber
            )?.uint32Value else {
                return nil
            }
            return PanelScreenGeometry(
                id: id,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }
}

@MainActor
private final class EscapeInputProbe: NSView {
    private weak var owner: CapturePanelController?
    private weak var hostedContent: NSView?

    init(owner: CapturePanelController) {
        self.owner = owner
        super.init(frame: .zero)
        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func installHostedContent(_ view: NSView) {
        hostedContent?.removeFromSuperview()
        hostedContent = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        owner?.notifyPointerBoundaryChanged()
    }

    override func mouseExited(with event: NSEvent) {
        owner?.notifyPointerBoundaryChanged()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            owner?.handleEscape()
        } else {
            super.keyDown(with: event)
        }
    }
}

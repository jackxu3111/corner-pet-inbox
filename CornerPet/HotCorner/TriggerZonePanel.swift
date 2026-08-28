import AppKit

@MainActor
final class TriggerZonePanel: NSPanel {
    struct ArmFrames: Equatable {
        let horizontal: CGRect
        let vertical: CGRect
    }

    let trackingView: TriggerTrackingView

    init(frame: CGRect, onBoundaryChanged: @escaping () -> Void) {
        trackingView = TriggerTrackingView(onBoundaryChanged: onBoundaryChanged)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        contentView = trackingView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        ignoresMouseEvents = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
    }

    static func frames(for screenFrame: CGRect, corner: TriggerCorner) -> ArmFrames {
        let regions = HotCornerGeometry.regions(frame: screenFrame, corner: corner)
        return ArmFrames(horizontal: regions[0], vertical: regions[1])
    }
}

@MainActor
final class TriggerTrackingView: NSView {
    let onBoundaryChanged: () -> Void

    private var ownedTrackingArea: NSTrackingArea?

    init(onBoundaryChanged: @escaping () -> Void) {
        self.onBoundaryChanged = onBoundaryChanged
        super.init(frame: .zero)
        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let ownedTrackingArea {
            removeTrackingArea(ownedTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        ownedTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onBoundaryChanged()
    }

    override func mouseExited(with event: NSEvent) {
        onBoundaryChanged()
    }
}

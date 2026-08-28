import AppKit
import SwiftUI

@MainActor
final class PetReminderPanelController {
    private let pointerLocationProvider: @MainActor () -> CGPoint
    private let onOpenInbox: @MainActor () -> Void
    private let onSnooze: @MainActor () -> Void
    private let onDismissToday: @MainActor () -> Void

    private(set) var panel: PetReminderPanel?
    private(set) var currentScreenID: UInt32?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    init(
        pointerLocationProvider: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        onOpenInbox: @escaping @MainActor () -> Void,
        onSnooze: @escaping @MainActor () -> Void,
        onDismissToday: @escaping @MainActor () -> Void
    ) {
        self.pointerLocationProvider = pointerLocationProvider
        self.onOpenInbox = onOpenInbox
        self.onSnooze = onSnooze
        self.onDismissToday = onDismissToday
    }

    func present(
        corner: TriggerCorner,
        screens: [ScreenSnapshot],
        primaryDisplayID: UInt32?
    ) {
        guard let placement = PetReminderPositioner.placement(
            screens: screens,
            primaryDisplayID: primaryDisplayID,
            pointerLocation: pointerLocationProvider(),
            corner: corner
        ) else {
            return
        }

        let panel = self.panel ?? makePanel(frame: placement.frame)
        panel.setFrame(placement.frame, display: true)
        installContent(corner: corner, in: panel)
        currentScreenID = placement.screenID
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func updatePlacement(
        corner: TriggerCorner,
        screens: [ScreenSnapshot],
        primaryDisplayID: UInt32?
    ) {
        guard isVisible,
              let placement = PetReminderPositioner.placement(
                screens: screens,
                primaryDisplayID: primaryDisplayID,
                pointerLocation: pointerLocationProvider(),
                corner: corner
              ) else {
            return
        }
        panel?.setFrame(placement.frame, display: true)
        if let panel {
            installContent(corner: corner, in: panel)
        }
        currentScreenID = placement.screenID
    }

    func dismiss() {
        panel?.orderOut(nil)
        currentScreenID = nil
    }

    private func makePanel(frame: CGRect) -> PetReminderPanel {
        let panel = PetReminderPanel(contentRect: frame)
        return panel
    }

    private func installContent(corner: TriggerCorner, in panel: PetReminderPanel) {
        let hostingView = NSHostingView(rootView: CatReminderView(
            corner: corner,
            onOpenInbox: onOpenInbox,
            onSnooze: onSnooze,
            onDismissToday: onDismissToday
        ))
        hostingView.frame = panel.contentView?.bounds
            ?? CGRect(origin: .zero, size: panel.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }
}

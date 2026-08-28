import SwiftUI

struct CornerPanelDragRegion: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> CornerPanelDragRegionView {
        CornerPanelDragRegionView(isEnabled: isEnabled)
    }

    func updateNSView(_ nsView: CornerPanelDragRegionView, context: Context) {
        nsView.isEnabled = isEnabled
    }
}

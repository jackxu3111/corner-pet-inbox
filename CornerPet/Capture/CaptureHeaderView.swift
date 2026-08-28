import SwiftUI

struct CaptureHeaderView: View {
    let isPinned: Bool
    let pinAvailable: Bool
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.12), in: Circle())
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("CornerPet")
                    .font(.headline)
                Text("角落灵感箱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)

            Spacer(minLength: 8)

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!pinAvailable)
            .help(isPinned ? "取消置顶 / Unpin" : "置顶 / Pin")
            .accessibilityLabel(isPinned ? "取消置顶 / Unpin" : "置顶 / Pin")
            .accessibilityIdentifier("capture.pin")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.header")
    }
}

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
                Text(L10n.captureHeaderSubtitle)
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
            .help(Text(pinLabel))
            .accessibilityLabel(Text(pinLabel))
            .accessibilityIdentifier("capture.pin")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture.header")
    }

    private var pinLabel: LocalizedStringResource {
        isPinned ? L10n.captureUnpin : L10n.capturePin
    }
}

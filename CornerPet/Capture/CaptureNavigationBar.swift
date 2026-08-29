import SwiftUI

struct CaptureNavigationBar: View {
    let selectedDestination: CaptureDestination
    let onSelect: (CaptureDestination) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureDestination.allCases) { destination in
                if destination == .settings {
                    Button(action: onOpenSettings) {
                        NavigationItemLabel(
                            destination: destination,
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(destination.title))
                    .accessibilityIdentifier("nav.\(destination.rawValue)")
                } else {
                    Button {
                        onSelect(destination)
                    } label: {
                        NavigationItemLabel(
                            destination: destination,
                            isSelected: selectedDestination == destination
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(destination.title))
                    .accessibilityValue(
                        selectedDestination == destination
                            ? L10n.localized(L10n.accessibilitySelected, locale: locale)
                            : ""
                    )
                    .accessibilityIdentifier("nav.\(destination.rawValue)")
                }
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NavigationItemLabel: View {
    let destination: CaptureDestination
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(destination.title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isSelected ? Color.accentColor.opacity(0.11) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .contentShape(Rectangle())
    }
}

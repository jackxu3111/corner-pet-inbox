import SwiftUI

struct CaptureNavigationBar: View {
    let selectedDestination: CaptureDestination
    let onSelect: (CaptureDestination) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureDestination.allCases) { destination in
                if destination == .settings {
                    SettingsLink {
                        NavigationItemLabel(
                            destination: destination,
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(destination.chineseTitle) / \(destination.englishTitle)")
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
                    .accessibilityLabel("\(destination.chineseTitle) / \(destination.englishTitle)")
                    .accessibilityValue(selectedDestination == destination ? "已选择 / Selected" : "")
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
            Text(destination.chineseTitle)
                .font(.caption2.weight(.medium))
            Text(destination.englishTitle)
                .font(.caption2)
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

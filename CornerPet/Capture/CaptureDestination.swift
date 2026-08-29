import CoreGraphics
import Foundation

enum CaptureDestination: String, CaseIterable, Identifiable {
    case inbox
    case favorites
    case archive
    case settings

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .inbox: L10n.navInbox
        case .favorites: L10n.navFavorites
        case .archive: L10n.navArchive
        case .settings: L10n.navSettings
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .favorites: "star"
        case .archive: "archivebox"
        case .settings: "gearshape"
        }
    }
}

enum CaptureLayout {
    static let panelSize = CGSize(width: 360, height: 450)
    static let outerPadding: CGFloat = 12
    static let headerHeight: CGFloat = 42
    static let contentSpacing: CGFloat = 8
    static let topDragRegionHeight: CGFloat = outerPadding + headerHeight + contentSpacing
    static let navigationHeight: CGFloat = 54
    static let inputMinimumHeight: CGFloat = 30
    static let inputMaximumHeight: CGFloat = 110
    static let inputVisibleLineLimit = 5

    static func inputHeight(contentHeight: CGFloat) -> CGFloat {
        min(inputMaximumHeight, max(inputMinimumHeight, contentHeight))
    }

    static func inputHeight(
        contentHeight: CGFloat,
        visualLineCount: Int
    ) -> CGFloat {
        guard visualLineCount <= inputVisibleLineLimit else {
            return inputMaximumHeight
        }
        return inputHeight(contentHeight: contentHeight)
    }
}

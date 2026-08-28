import CoreGraphics
import Foundation

struct PinnedPanelSizeStore {
    static let defaultsKey = "com.jack.cornerpet.pinnedPanelSize"
    static let defaultSize = CGSize(width: 360, height: 450)
    static let minimumSize = CGSize(width: 280, height: 320)
    static let maximumSize = CGSize(width: 480, height: 640)

    private enum Field {
        static let width = "width"
        static let height = "height"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CGSize {
        guard let values = defaults.dictionary(forKey: Self.defaultsKey) else {
            return Self.defaultSize
        }

        let width = finiteDimension(
            values[Field.width],
            fallback: Self.defaultSize.width
        )
        let height = finiteDimension(
            values[Field.height],
            fallback: Self.defaultSize.height
        )
        return Self.clamped(CGSize(width: width, height: height))
    }

    func save(_ size: CGSize) {
        let clamped = Self.clamped(size)
        defaults.set([
            Field.width: Double(clamped.width),
            Field.height: Double(clamped.height)
        ], forKey: Self.defaultsKey)
    }

    static func clamped(_ size: CGSize) -> CGSize {
        CGSize(
            width: clamp(
                size.width,
                fallback: defaultSize.width,
                minimum: minimumSize.width,
                maximum: maximumSize.width
            ),
            height: clamp(
                size.height,
                fallback: defaultSize.height,
                minimum: minimumSize.height,
                maximum: maximumSize.height
            )
        )
    }

    private func finiteDimension(_ raw: Any?, fallback: CGFloat) -> CGFloat {
        let number = raw as? NSNumber
        let value = number?.doubleValue ?? Double.nan
        guard value.isFinite, value > 0 else { return fallback }
        return CGFloat(value)
    }

    private static func clamp(
        _ value: CGFloat,
        fallback: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return min(maximum, max(minimum, value))
    }
}

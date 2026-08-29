import Foundation

struct LocalizationEntry: Sendable {
    let key: String
    let resource: LocalizedStringResource
}

enum L10n {
    static let captureSaveFailed: LocalizedStringResource = "capture.error.saveFailed"

    static let allEntries = [
        LocalizationEntry(
            key: "capture.error.saveFailed",
            resource: captureSaveFailed
        )
    ]

    static func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = locale
        return String(localized: localizedResource)
    }
}

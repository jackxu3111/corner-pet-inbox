import SwiftUI

@MainActor
struct AppLocaleScope<Content: View>: View {
    let settings: AppSettings
    @ViewBuilder let content: () -> Content

    var locale: Locale {
        settings.language.locale
    }

    var body: some View {
        content()
            .environment(\.locale, locale)
    }
}

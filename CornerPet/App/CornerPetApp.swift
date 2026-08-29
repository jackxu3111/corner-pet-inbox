import SwiftUI

@main
struct CornerPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppLocaleScope(settings: appDelegate.appSettings) {
                CornerPetSettingsView(
                    settings: appDelegate.appSettings,
                    launchAtLogin: appDelegate.launchAtLoginController
                )
            }
        }
        .environment(\.locale, appDelegate.appSettings.language.locale)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text(L10n.appSettings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button(action: appDelegate.focusLibrarySearch) {
                    Text(L10n.appFind)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

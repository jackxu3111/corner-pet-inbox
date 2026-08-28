import SwiftUI

@main
struct CornerPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            CornerPetSettingsView(
                settings: appDelegate.appSettings,
                launchAtLogin: appDelegate.launchAtLoginController
            )
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("CornerPet 设置… / Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

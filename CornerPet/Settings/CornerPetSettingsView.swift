import SwiftUI

struct CornerPetSettingsView: View {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                Picker(selection: triggerCornerBinding) {
                    ForEach(TriggerCorner.allCases, id: \.rawValue) { corner in
                        Text(cornerTitle(corner)).tag(corner)
                    }
                } label: {
                    Text(L10n.triggerCorner)
                }
                .accessibilityIdentifier("settings.triggerCorner")
                Picker(selection: displayScopeBinding) {
                    ForEach(DisplayScope.allCases) { scope in
                        Text(displayScopeTitle(scope)).tag(scope)
                    }
                } label: {
                    Text(L10n.settingsDisplayScope)
                }
                .accessibilityIdentifier("settings.displayScope")
                LabeledContent {
                    Text(settings.fixedDwellDuration, format: .number.precision(.fractionLength(1)))
                    Text(L10n.seconds)
                } label: {
                    Text(L10n.settingsDwell)
                }
            } header: {
                Text(L10n.triggerSection)
            }

            Section {
                Toggle(isOn: reminderEnabledBinding) {
                    Text(L10n.reminderEnabled)
                }
                    .accessibilityIdentifier("settings.reminderEnabled")
                DatePicker(
                    selection: reminderDateBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    Text(L10n.reminderTime)
                }
                .disabled(!settings.reminderEnabled)
                .accessibilityIdentifier("settings.reminderTime")
                Text(L10n.reminderExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.reminderSection)
            }

            Section {
                Picker(selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageTitle(language)).tag(language)
                    }
                } label: {
                    Text(L10n.languagePreference)
                }
                .accessibilityIdentifier("settings.language")
                Text(L10n.languageExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.language.help")
            } header: {
                Text(L10n.languageSection)
            }

            Section {
                Toggle(isOn: launchAtLoginBinding) {
                    Text(L10n.launchAtLogin)
                }
                    .disabled(launchAtLogin.state == .unavailable)
                    .accessibilityIdentifier("settings.launchAtLogin")

                if launchAtLogin.state == .requiresApproval {
                    Label {
                        Text(L10n.launchApproval)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.launch.approval")
                    Button(action: launchAtLogin.openSystemSettings) {
                        Text(L10n.openLoginItems)
                    }
                    .accessibilityIdentifier("settings.launch.openLoginItems")
                } else if launchAtLogin.state == .unavailable {
                    Label {
                        Text(L10n.launchUnavailable)
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.launch.unavailable")
                }

                if launchAtLogin.errorMessage != nil {
                    Text(L10n.launchError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.launch.error")
                }
            } header: {
                Text(L10n.startupSection)
            }

            Section {
                Text(L10n.hotCornerConflictBody)
                    .accessibilityIdentifier("settings.conflictHelp.body")
                Text(L10n.noInputMonitoring)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: openSystemSettings) {
                    Text(L10n.openSystemSettings)
                }
                    .accessibilityIdentifier("settings.conflictHelp.openSystemSettings")
            } header: {
                Text(L10n.hotCornerConflictSection)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .task {
            launchAtLogin.refresh()
        }
    }

    private var triggerCornerBinding: Binding<TriggerCorner> {
        Binding(
            get: { settings.triggerCorner },
            set: settings.setTriggerCorner
        )
    }

    private var displayScopeBinding: Binding<DisplayScope> {
        Binding(
            get: { settings.displayScope },
            set: settings.setDisplayScope
        )
    }

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(
                        hour: settings.dailyReminderMinutes / 60,
                        minute: settings.dailyReminderMinutes % 60
                    )
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                guard let hour = components.hour, let minute = components.minute else { return }
                settings.setDailyReminderMinutes(hour * 60 + minute)
            }
        )
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.reminderEnabled },
            set: settings.setReminderEnabled
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { settings.language },
            set: settings.setLanguage
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: launchAtLogin.setEnabled
        )
    }

    private func cornerTitle(_ corner: TriggerCorner) -> LocalizedStringResource {
        switch corner {
        case .topLeft: L10n.cornerTopLeft
        case .topRight: L10n.cornerTopRight
        case .bottomLeft: L10n.cornerBottomLeft
        case .bottomRight: L10n.cornerBottomRight
        }
    }

    private func displayScopeTitle(_ scope: DisplayScope) -> LocalizedStringResource {
        switch scope {
        case .primary: L10n.displayPrimary
        case .all: L10n.displayAll
        }
    }

    private func languageTitle(_ language: AppLanguage) -> LocalizedStringResource {
        switch language {
        case .system: L10n.languageSystem
        case .simplifiedChinese: L10n.languageZhHans
        case .english: L10n.languageEnglish
        }
    }

    private func openSystemSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

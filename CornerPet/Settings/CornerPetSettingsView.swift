import SwiftUI

struct CornerPetSettingsView: View {
    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section("触发 / Trigger") {
                Picker("触发角 / Trigger corner", selection: triggerCornerBinding) {
                    ForEach(TriggerCorner.allCases, id: \.rawValue) { corner in
                        Text(cornerTitle(corner)).tag(corner)
                    }
                }
                .accessibilityIdentifier("settings.triggerCorner")
                Picker("显示范围 / Displays", selection: displayScopeBinding) {
                    ForEach(DisplayScope.allCases) { scope in
                        Text(displayScopeTitle(scope)).tag(scope)
                    }
                }
                .accessibilityIdentifier("settings.displayScope")
                LabeledContent("停留时间 / Dwell") {
                    Text(settings.fixedDwellDuration, format: .number.precision(.fractionLength(1)))
                    Text(" 秒 / s")
                }
            }

            Section("每日提醒 / Daily reminder") {
                DatePicker(
                    "提醒时间 / Reminder time",
                    selection: reminderDateBinding,
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("settings.reminderTime")
                Text("目前只保存提醒时间；每日提醒与小猫功能将在后续版本启用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("The reminder time is saved now. Scheduling and the pet will arrive in a later version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("语言 / Language") {
                Picker("语言偏好 / Language preference", selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(languageTitle(language)).tag(language)
                    }
                }
                .accessibilityIdentifier("settings.language")
                Text("语言偏好已保存；完整本地化将在后续版本提供，当前界面仍保留现有中英混合文案。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("The preference is saved; full localization will arrive in a later version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("启动 / Startup") {
                Toggle("登录时启动 / Launch at login", isOn: launchAtLoginBinding)
                    .disabled(launchAtLogin.state == .unavailable)
                    .accessibilityIdentifier("settings.launchAtLogin")

                if launchAtLogin.state == .requiresApproval {
                    Label(
                        "需要在系统设置中批准 / Approval required in System Settings",
                        systemImage: "exclamationmark.circle"
                    )
                    .foregroundStyle(.orange)
                    Button("打开登录项设置 / Open Login Items", action: launchAtLogin.openSystemSettings)
                } else if launchAtLogin.state == .unavailable {
                    Label(
                        "当前构建无法注册登录项 / Login item unavailable in this build",
                        systemImage: "xmark.circle"
                    )
                    .foregroundStyle(.secondary)
                }

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("热角冲突帮助 / Hot Corner conflicts") {
                Text("CornerPet 无法检测 macOS 触发角是否冲突。若同一角落已分配系统操作，两者可能同时响应。请前往“系统设置 → 桌面与程序坞 → 触发角…”，清除该角落的系统操作，或在 CornerPet 中选择其他角落。CornerPet 不会读取或更改这些系统设置。")
                    .accessibilityIdentifier("settings.conflictHelp.body")
                Text("CornerPet can’t detect whether macOS Hot Corners conflict with this setting. Go to “System Settings → Desktop & Dock → Hot Corners…” to clear the system action, or choose another CornerPet corner. CornerPet never reads or changes these system settings.")
                    .foregroundStyle(.secondary)
                Text("不需要“输入监控”权限 / No Input Monitoring permission is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("打开系统设置 / Open System Settings", action: openSystemSettings)
                    .accessibilityIdentifier("settings.conflictHelp.openSystemSettings")
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

    private func cornerTitle(_ corner: TriggerCorner) -> String {
        switch corner {
        case .topLeft: "左上 / Top Left"
        case .topRight: "右上 / Top Right"
        case .bottomLeft: "左下 / Bottom Left"
        case .bottomRight: "右下 / Bottom Right"
        }
    }

    private func displayScopeTitle(_ scope: DisplayScope) -> String {
        switch scope {
        case .primary: "主屏 / Primary Display"
        case .all: "所有屏幕 / All Displays"
        }
    }

    private func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .system: "跟随系统 / System Default"
        case .simplifiedChinese: "简体中文 / Simplified Chinese"
        case .english: "English / 英语"
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

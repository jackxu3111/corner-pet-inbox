import CoreGraphics
import Foundation
import Observation

enum DisplayScope: String, CaseIterable, Identifiable, Sendable {
    case primary
    case all

    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

enum AppSettingsStorageKey {
    static let displayScope = "CornerPet.displayScope"
    static let dailyReminderMinutes = "CornerPet.dailyReminderMinutes"
    static let reminderEnabled = "CornerPet.reminderEnabled"
    static let language = "CornerPet.language"
}

struct AppSettingsSnapshot: Equatable, Sendable {
    let triggerCorner: TriggerCorner
    let displayScope: DisplayScope
    let lastPinnedSize: CGSize
    let dailyReminderMinutes: Int
    let reminderEnabled: Bool
    let language: AppLanguage
}

enum AppSettingsField: Equatable, Sendable {
    case triggerCorner
    case displayScope
    case lastPinnedSize
    case dailyReminderMinutes
    case reminderEnabled
    case language
}

struct AppSettingsChange: Equatable, Sendable {
    let field: AppSettingsField
    let snapshot: AppSettingsSnapshot
}

@MainActor
@Observable
final class AppSettings {
    static let defaultReminderMinutes = 9 * 60

    private let defaults: UserDefaults
    private let triggerCornerStore: TriggerCornerStore
    private let pinnedPanelSizeStore: PinnedPanelSizeStore

    private(set) var triggerCorner: TriggerCorner
    private(set) var displayScope: DisplayScope
    private(set) var lastPinnedSize: CGSize
    private(set) var dailyReminderMinutes: Int
    private(set) var reminderEnabled: Bool
    private(set) var language: AppLanguage

    @ObservationIgnored
    var onChange: ((AppSettingsChange) -> Void)?

    var fixedDwellDuration: TimeInterval {
        DwellTiming.duration
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            triggerCorner: triggerCorner,
            displayScope: displayScope,
            lastPinnedSize: lastPinnedSize,
            dailyReminderMinutes: dailyReminderMinutes,
            reminderEnabled: reminderEnabled,
            language: language
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        triggerCornerStore = TriggerCornerStore(defaults: defaults)
        pinnedPanelSizeStore = PinnedPanelSizeStore(defaults: defaults)
        triggerCorner = triggerCornerStore.load()
        displayScope = defaults.string(forKey: AppSettingsStorageKey.displayScope)
            .flatMap(DisplayScope.init(rawValue:)) ?? .primary
        lastPinnedSize = pinnedPanelSizeStore.load()
        dailyReminderMinutes = Self.validReminderMinutes(
            defaults.object(forKey: AppSettingsStorageKey.dailyReminderMinutes)
        )
        reminderEnabled = Self.reminderEnabled(
            defaults.object(forKey: AppSettingsStorageKey.reminderEnabled)
        )
        language = defaults.string(forKey: AppSettingsStorageKey.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func setTriggerCorner(_ corner: TriggerCorner) {
        guard triggerCorner != corner else { return }
        triggerCornerStore.save(corner)
        triggerCorner = corner
        publish(.triggerCorner)
    }

    func setDisplayScope(_ scope: DisplayScope) {
        guard displayScope != scope else { return }
        defaults.set(scope.rawValue, forKey: AppSettingsStorageKey.displayScope)
        displayScope = scope
        publish(.displayScope)
    }

    func setLastPinnedSize(_ size: CGSize) {
        let clamped = PinnedPanelSizeStore.clamped(size)
        guard lastPinnedSize != clamped else { return }
        pinnedPanelSizeStore.save(clamped)
        lastPinnedSize = clamped
        publish(.lastPinnedSize)
    }

    func setDailyReminderMinutes(_ minutes: Int) {
        let validated = Self.validReminderMinutes(minutes)
        guard dailyReminderMinutes != validated else { return }
        defaults.set(validated, forKey: AppSettingsStorageKey.dailyReminderMinutes)
        dailyReminderMinutes = validated
        publish(.dailyReminderMinutes)
    }

    func setReminderEnabled(_ enabled: Bool) {
        guard reminderEnabled != enabled else { return }
        defaults.set(enabled, forKey: AppSettingsStorageKey.reminderEnabled)
        reminderEnabled = enabled
        publish(.reminderEnabled)
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        defaults.set(language.rawValue, forKey: AppSettingsStorageKey.language)
        self.language = language
        publish(.language)
    }

    private func publish(_ field: AppSettingsField) {
        onChange?(AppSettingsChange(field: field, snapshot: snapshot))
    }

    private static func validReminderMinutes(_ raw: Any?) -> Int {
        guard let number = raw as? NSNumber else {
            return defaultReminderMinutes
        }
        return validReminderMinutes(number.intValue)
    }

    private static func validReminderMinutes(_ minutes: Int) -> Int {
        (0 ..< 24 * 60).contains(minutes) ? minutes : defaultReminderMinutes
    }

    private static func reminderEnabled(_ raw: Any?) -> Bool {
        (raw as? NSNumber)?.boolValue ?? true
    }
}

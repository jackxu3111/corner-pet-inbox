import Foundation

struct LocalizationEntry: Sendable {
    let key: String
    let resource: LocalizedStringResource
}

enum L10n {
    static let accessibilityEditAction: LocalizedStringResource = "accessibility.editAction"
    static let accessibilitySelected: LocalizedStringResource = "accessibility.selected"
    static let appFind: LocalizedStringResource = "app.command.find"
    static let appSettings: LocalizedStringResource = "app.command.settings"
    static let archiveEmpty: LocalizedStringResource = "archive.empty"
    static let archiveLoadFailed: LocalizedStringResource = "archive.loadFailed"
    static let archiveSearch: LocalizedStringResource = "archive.search"
    static let captureSaveFailed: LocalizedStringResource = "capture.error.saveFailed"
    static let captureHeaderSubtitle: LocalizedStringResource = "capture.header.subtitle"
    static let captureInputLabel: LocalizedStringResource = "capture.input.label"
    static let captureInputPlaceholder: LocalizedStringResource = "capture.input.placeholder"
    static let capturePin: LocalizedStringResource = "capture.pin"
    static let captureUnpin: LocalizedStringResource = "capture.unpin"
    static let cancel: LocalizedStringResource = "common.cancel"
    static let clearSearch: LocalizedStringResource = "common.clearSearch"
    static let delete: LocalizedStringResource = "common.delete"
    static let deleteConfirmation: LocalizedStringResource = "common.deleteConfirmation"
    static let deleteFailed: LocalizedStringResource = "common.deleteFailed"
    static let deletePermanent: LocalizedStringResource = "common.deletePermanent"
    static let dismiss: LocalizedStringResource = "common.dismiss"
    static let editIdea: LocalizedStringResource = "common.editIdea"
    static let noMatches: LocalizedStringResource = "common.noMatches"
    static let retry: LocalizedStringResource = "common.retry"
    static let saveFailed: LocalizedStringResource = "common.saveFailed"
    static let undo: LocalizedStringResource = "common.undo"
    static let favoriteAdd: LocalizedStringResource = "favorites.add"
    static let favoriteAddFailedHelp: LocalizedStringResource = "favorites.addFailedHelp"
    static let favoritesEmpty: LocalizedStringResource = "favorites.empty"
    static let favoritesLoadFailed: LocalizedStringResource = "favorites.loadFailed"
    static let favoriteRemove: LocalizedStringResource = "favorites.remove"
    static let favoriteRemoveFailedHelp: LocalizedStringResource = "favorites.removeFailedHelp"
    static let favoriteRetryAdd: LocalizedStringResource = "favorites.retryAdd"
    static let favoriteRetryRemove: LocalizedStringResource = "favorites.retryRemove"
    static let favoritesSearch: LocalizedStringResource = "favorites.search"
    static let archiveFailedHelp: LocalizedStringResource = "inbox.archiveFailedHelp"
    static let inboxArchived: LocalizedStringResource = "inbox.archived"
    static let completeArchive: LocalizedStringResource = "inbox.completeArchive"
    static let inboxEmpty: LocalizedStringResource = "inbox.empty"
    static let inboxLoadFailed: LocalizedStringResource = "inbox.loadFailed"
    static let restoreFailed: LocalizedStringResource = "inbox.restoreFailed"
    static let retryArchive: LocalizedStringResource = "inbox.retryArchive"
    static let navArchive: LocalizedStringResource = "nav.archive"
    static let navFavorites: LocalizedStringResource = "nav.favorites"
    static let navInbox: LocalizedStringResource = "nav.inbox"
    static let navSettings: LocalizedStringResource = "nav.settings"
    static let persistenceRecovery: LocalizedStringResource = "persistence.error.recovery"
    static let persistenceTitle: LocalizedStringResource = "persistence.error.title"
    static let reminderDismissToday: LocalizedStringResource = "reminder.dismissToday"
    static let reminderOpenInbox: LocalizedStringResource = "reminder.openInbox"
    static let reminderSnooze: LocalizedStringResource = "reminder.snooze"
    static let reminderTitle: LocalizedStringResource = "reminder.title"
    static let cornerBottomLeft: LocalizedStringResource = "settings.corner.bottomLeft"
    static let cornerBottomRight: LocalizedStringResource = "settings.corner.bottomRight"
    static let cornerTopLeft: LocalizedStringResource = "settings.corner.topLeft"
    static let cornerTopRight: LocalizedStringResource = "settings.corner.topRight"
    static let displayAll: LocalizedStringResource = "settings.display.all"
    static let displayPrimary: LocalizedStringResource = "settings.display.primary"
    static let settingsDisplayScope: LocalizedStringResource = "settings.displayScope"
    static let settingsDwell: LocalizedStringResource = "settings.dwell"
    static let hotCornerConflictBody: LocalizedStringResource = "settings.hotCornerConflictBody"
    static let languageEnglish: LocalizedStringResource = "settings.language.english"
    static let languageSystem: LocalizedStringResource = "settings.language.system"
    static let languageZhHans: LocalizedStringResource = "settings.language.zhHans"
    static let languageExplanation: LocalizedStringResource = "settings.languageExplanation"
    static let languagePreference: LocalizedStringResource = "settings.languagePreference"
    static let launchApproval: LocalizedStringResource = "settings.launchApproval"
    static let launchAtLogin: LocalizedStringResource = "settings.launchAtLogin"
    static let launchError: LocalizedStringResource = "settings.launchError"
    static let launchUnavailable: LocalizedStringResource = "settings.launchUnavailable"
    static let noInputMonitoring: LocalizedStringResource = "settings.noInputMonitoring"
    static let openLoginItems: LocalizedStringResource = "settings.openLoginItems"
    static let openSystemSettings: LocalizedStringResource = "settings.openSystemSettings"
    static let reminderEnabled: LocalizedStringResource = "settings.reminderEnabled"
    static let reminderExplanation: LocalizedStringResource = "settings.reminderExplanation"
    static let reminderTime: LocalizedStringResource = "settings.reminderTime"
    static let seconds: LocalizedStringResource = "settings.seconds"
    static let hotCornerConflictSection: LocalizedStringResource = "settings.section.hotCornerConflict"
    static let languageSection: LocalizedStringResource = "settings.section.language"
    static let reminderSection: LocalizedStringResource = "settings.section.reminder"
    static let startupSection: LocalizedStringResource = "settings.section.startup"
    static let triggerSection: LocalizedStringResource = "settings.section.trigger"
    static let triggerCorner: LocalizedStringResource = "settings.triggerCorner"

    static let allEntries: [LocalizationEntry] = [
        entry("accessibility.editAction", accessibilityEditAction),
        entry("accessibility.selected", accessibilitySelected),
        entry("app.command.find", appFind),
        entry("app.command.settings", appSettings),
        entry("archive.empty", archiveEmpty),
        entry("archive.loadFailed", archiveLoadFailed),
        entry("archive.search", archiveSearch),
        entry("capture.error.saveFailed", captureSaveFailed),
        entry("capture.header.subtitle", captureHeaderSubtitle),
        entry("capture.input.label", captureInputLabel),
        entry("capture.input.placeholder", captureInputPlaceholder),
        entry("capture.pin", capturePin),
        entry("capture.unpin", captureUnpin),
        entry("common.cancel", cancel),
        entry("common.clearSearch", clearSearch),
        entry("common.delete", delete),
        entry("common.deleteConfirmation", deleteConfirmation),
        entry("common.deleteFailed", deleteFailed),
        entry("common.deletePermanent", deletePermanent),
        entry("common.dismiss", dismiss),
        entry("common.editIdea", editIdea),
        entry("common.noMatches", noMatches),
        entry("common.retry", retry),
        entry("common.saveFailed", saveFailed),
        entry("common.undo", undo),
        entry("favorites.add", favoriteAdd),
        entry("favorites.addFailedHelp", favoriteAddFailedHelp),
        entry("favorites.empty", favoritesEmpty),
        entry("favorites.loadFailed", favoritesLoadFailed),
        entry("favorites.remove", favoriteRemove),
        entry("favorites.removeFailedHelp", favoriteRemoveFailedHelp),
        entry("favorites.retryAdd", favoriteRetryAdd),
        entry("favorites.retryRemove", favoriteRetryRemove),
        entry("favorites.search", favoritesSearch),
        entry("inbox.archiveFailedHelp", archiveFailedHelp),
        entry("inbox.archived", inboxArchived),
        entry("inbox.completeArchive", completeArchive),
        entry("inbox.empty", inboxEmpty),
        entry("inbox.loadFailed", inboxLoadFailed),
        entry("inbox.restoreFailed", restoreFailed),
        entry("inbox.retryArchive", retryArchive),
        entry("nav.archive", navArchive),
        entry("nav.favorites", navFavorites),
        entry("nav.inbox", navInbox),
        entry("nav.settings", navSettings),
        entry("persistence.error.recovery", persistenceRecovery),
        entry("persistence.error.title", persistenceTitle),
        entry("reminder.dismissToday", reminderDismissToday),
        entry("reminder.openInbox", reminderOpenInbox),
        entry("reminder.snooze", reminderSnooze),
        entry("reminder.title", reminderTitle),
        entry("settings.corner.bottomLeft", cornerBottomLeft),
        entry("settings.corner.bottomRight", cornerBottomRight),
        entry("settings.corner.topLeft", cornerTopLeft),
        entry("settings.corner.topRight", cornerTopRight),
        entry("settings.display.all", displayAll),
        entry("settings.display.primary", displayPrimary),
        entry("settings.displayScope", settingsDisplayScope),
        entry("settings.dwell", settingsDwell),
        entry("settings.hotCornerConflictBody", hotCornerConflictBody),
        entry("settings.language.english", languageEnglish),
        entry("settings.language.system", languageSystem),
        entry("settings.language.zhHans", languageZhHans),
        entry("settings.languageExplanation", languageExplanation),
        entry("settings.languagePreference", languagePreference),
        entry("settings.launchApproval", launchApproval),
        entry("settings.launchAtLogin", launchAtLogin),
        entry("settings.launchError", launchError),
        entry("settings.launchUnavailable", launchUnavailable),
        entry("settings.noInputMonitoring", noInputMonitoring),
        entry("settings.openLoginItems", openLoginItems),
        entry("settings.openSystemSettings", openSystemSettings),
        entry("settings.reminderEnabled", reminderEnabled),
        entry("settings.reminderExplanation", reminderExplanation),
        entry("settings.reminderTime", reminderTime),
        entry("settings.seconds", seconds),
        entry("settings.section.hotCornerConflict", hotCornerConflictSection),
        entry("settings.section.language", languageSection),
        entry("settings.section.reminder", reminderSection),
        entry("settings.section.startup", startupSection),
        entry("settings.section.trigger", triggerSection),
        entry("settings.triggerCorner", triggerCorner)
    ]

    static func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var localizedResource = resource
        localizedResource.locale = locale
        return String(localized: localizedResource)
    }

    private static func entry(
        _ key: String,
        _ resource: LocalizedStringResource
    ) -> LocalizationEntry {
        LocalizationEntry(key: key, resource: resource)
    }
}

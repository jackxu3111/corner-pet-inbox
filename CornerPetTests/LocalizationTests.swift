import Foundation
import SwiftUI
import XCTest

@testable import CornerPet

@MainActor
final class LocalizationTests: XCTestCase {
    func testCatalogDeclaresTheCompleteTaskThirteenCopySurface() {
        let expectedKeys: Set<String> = [
            "accessibility.editAction",
            "accessibility.selected",
            "app.command.find",
            "app.command.settings",
            "archive.empty",
            "archive.loadFailed",
            "archive.search",
            "capture.error.saveFailed",
            "capture.header.subtitle",
            "capture.input.label",
            "capture.input.placeholder",
            "capture.pin",
            "capture.unpin",
            "common.cancel",
            "common.clearSearch",
            "common.delete",
            "common.deleteConfirmation",
            "common.deleteFailed",
            "common.deletePermanent",
            "common.dismiss",
            "common.editIdea",
            "common.noMatches",
            "common.retry",
            "common.saveFailed",
            "common.undo",
            "favorites.add",
            "favorites.empty",
            "favorites.loadFailed",
            "favorites.remove",
            "favorites.search",
            "inbox.archiveFailedHelp",
            "inbox.archived",
            "inbox.completeArchive",
            "inbox.empty",
            "inbox.loadFailed",
            "inbox.restoreFailed",
            "inbox.retryArchive",
            "nav.archive",
            "nav.favorites",
            "nav.inbox",
            "nav.settings",
            "persistence.error.recovery",
            "persistence.error.title",
            "reminder.dismissToday",
            "reminder.openInbox",
            "reminder.snooze",
            "reminder.title",
            "settings.corner.bottomLeft",
            "settings.corner.bottomRight",
            "settings.corner.topLeft",
            "settings.corner.topRight",
            "settings.display.all",
            "settings.display.primary",
            "settings.displayScope",
            "settings.dwell",
            "settings.hotCornerConflictBody",
            "settings.language.english",
            "settings.language.system",
            "settings.language.zhHans",
            "settings.languageExplanation",
            "settings.languagePreference",
            "settings.launchApproval",
            "settings.launchAtLogin",
            "settings.launchError",
            "settings.launchUnavailable",
            "settings.noInputMonitoring",
            "settings.openLoginItems",
            "settings.openSystemSettings",
            "settings.reminderEnabled",
            "settings.reminderExplanation",
            "settings.reminderTime",
            "settings.seconds",
            "settings.section.hotCornerConflict",
            "settings.section.language",
            "settings.section.reminder",
            "settings.section.startup",
            "settings.section.trigger",
            "settings.triggerCorner"
        ]

        XCTAssertEqual(Set(L10n.allEntries.map(\.key)), expectedKeys)
    }

    func testAppLocaleScopeReadsTheCurrentLanguageWithoutCachingIt() {
        let settings = AppSettings(defaults: UserDefaults(
            suiteName: "CornerPet.LocalizationScope.\(UUID().uuidString)"
        )!)
        settings.setLanguage(.english)
        let scope = AppLocaleScope(settings: settings) {
            EmptyView()
        }

        XCTAssertEqual(scope.locale.identifier, "en")

        settings.setLanguage(.simplifiedChinese)

        XCTAssertEqual(scope.locale.identifier, "zh-Hans")
    }

    func testEveryDeclaredResourceResolvesInEnglishAndSimplifiedChinese() {
        for localeIdentifier in ["en", "zh-Hans"] {
            let locale = Locale(identifier: localeIdentifier)

            for entry in L10n.allEntries {
                let value = L10n.localized(entry.resource, locale: locale)

                XCTAssertFalse(value.isEmpty, "\(entry.key) is empty in \(localeIdentifier)")
                XCTAssertNotEqual(
                    value,
                    entry.key,
                    "\(entry.key) leaks its raw key in \(localeIdentifier)"
                )
            }
        }
    }

    func testCaptureSaveFailureHasActionableCopyInBothLanguages() {
        XCTAssertEqual(
            L10n.localized(L10n.captureSaveFailed, locale: Locale(identifier: "en")),
            "Couldn’t save. Your draft is still here—try again."
        )
        XCTAssertEqual(
            L10n.localized(L10n.captureSaveFailed, locale: Locale(identifier: "zh-Hans")),
            "无法保存。草稿仍在，请重试。"
        )
    }
}

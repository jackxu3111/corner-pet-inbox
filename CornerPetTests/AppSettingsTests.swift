import CoreGraphics
import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchAcceptedTaskElevenBehavior() {
        let settings = AppSettings(defaults: isolatedDefaults())

        XCTAssertEqual(settings.triggerCorner, .topLeft)
        XCTAssertEqual(settings.displayScope, .primary)
        XCTAssertEqual(settings.lastPinnedSize, CGSize(width: 360, height: 450))
        XCTAssertEqual(settings.dailyReminderMinutes, 9 * 60)
        XCTAssertTrue(settings.reminderEnabled)
        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(settings.fixedDwellDuration, 0.4)
    }

    func testEverySettingPersistsAcrossFreshRuntimeModels() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.setTriggerCorner(.bottomRight)
        settings.setDisplayScope(.all)
        settings.setLastPinnedSize(CGSize(width: 475, height: 625))
        settings.setDailyReminderMinutes(22 * 60 + 35)
        settings.setReminderEnabled(false)
        settings.setLanguage(.english)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.triggerCorner, .bottomRight)
        XCTAssertEqual(restored.displayScope, .all)
        XCTAssertEqual(restored.lastPinnedSize, CGSize(width: 475, height: 625))
        XCTAssertEqual(restored.dailyReminderMinutes, 22 * 60 + 35)
        XCTAssertFalse(restored.reminderEnabled)
        XCTAssertEqual(restored.language, .english)
    }

    func testInvalidPersistedValuesFallBackWithoutOverwritingLegacyKeys() {
        let defaults = isolatedDefaults()
        defaults.set("sideways", forKey: TriggerCornerStore.storageKey)
        defaults.set("externalOnly", forKey: AppSettingsStorageKey.displayScope)
        defaults.set(-1, forKey: AppSettingsStorageKey.dailyReminderMinutes)
        defaults.set("klingon", forKey: AppSettingsStorageKey.language)
        defaults.set([
            "width": Double.nan,
            "height": Double.infinity
        ], forKey: PinnedPanelSizeStore.defaultsKey)

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.triggerCorner, .topLeft)
        XCTAssertEqual(settings.displayScope, .primary)
        XCTAssertEqual(settings.lastPinnedSize, CGSize(width: 360, height: 450))
        XCTAssertEqual(settings.dailyReminderMinutes, 9 * 60)
        XCTAssertEqual(settings.language, .system)
        XCTAssertEqual(defaults.string(forKey: TriggerCornerStore.storageKey), "sideways")
        XCTAssertNotNil(defaults.dictionary(forKey: PinnedPanelSizeStore.defaultsKey))
    }

    func testExistingCornerAndSizeKeysAreAdoptedInPlace() {
        let defaults = isolatedDefaults()
        TriggerCornerStore(defaults: defaults).save(.topRight)
        PinnedPanelSizeStore(defaults: defaults).save(CGSize(width: 420, height: 510))

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.triggerCorner, .topRight)
        XCTAssertEqual(settings.lastPinnedSize, CGSize(width: 420, height: 510))
        XCTAssertNil(defaults.object(forKey: "CornerPet.settings.triggerCorner"))
        XCTAssertNil(defaults.object(forKey: "CornerPet.settings.lastPinnedSize"))
    }

    func testMutationValidatesPersistsThenPublishesOneTypedSnapshot() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        var changes: [AppSettingsChange] = []
        settings.onChange = { changes.append($0) }

        settings.setDailyReminderMinutes(10 * 60 + 10)
        settings.setLastPinnedSize(CGSize(width: 50, height: 5_000))

        XCTAssertEqual(changes.map(\.field), [.dailyReminderMinutes, .lastPinnedSize])
        XCTAssertEqual(changes[0].snapshot.dailyReminderMinutes, 10 * 60 + 10)
        XCTAssertEqual(changes[1].snapshot.lastPinnedSize, CGSize(width: 280, height: 640))
        XCTAssertEqual(
            defaults.integer(forKey: AppSettingsStorageKey.dailyReminderMinutes),
            10 * 60 + 10
        )
        XCTAssertEqual(
            PinnedPanelSizeStore(defaults: defaults).load(),
            CGSize(width: 280, height: 640)
        )
    }

    func testReminderEnabledPersistsThenPublishesTypedSnapshot() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        var changes: [AppSettingsChange] = []
        settings.onChange = { changes.append($0) }

        settings.setReminderEnabled(false)

        XCTAssertFalse(AppSettings(defaults: defaults).reminderEnabled)
        XCTAssertEqual(changes.map(\.field), [.reminderEnabled])
        XCTAssertFalse(changes[0].snapshot.reminderEnabled)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CornerPet.AppSettingsTests.\(UUID().uuidString)")!
    }
}

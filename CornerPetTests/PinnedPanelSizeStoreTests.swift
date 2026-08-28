import CoreGraphics
import Foundation
import XCTest

@testable import CornerPet

final class PinnedPanelSizeStoreTests: XCTestCase {
    func testPinnedSizeDefaultsTo360x450AndClampsBothAxes() {
        let defaults = isolatedDefaults()
        let store = PinnedPanelSizeStore(defaults: defaults)

        XCTAssertEqual(store.load(), CGSize(width: 360, height: 450))

        store.save(CGSize(width: 1, height: 10_000))

        XCTAssertEqual(store.load(), CGSize(width: 280, height: 640))
    }

    func testInvalidValuesUseSafeDefaultsAndDoNotPersistExtraState() {
        let defaults = isolatedDefaults()
        defaults.set([
            "width": Double.nan,
            "height": Double.infinity,
            "corner": "topLeft",
            "isPinned": true
        ], forKey: PinnedPanelSizeStore.defaultsKey)
        let store = PinnedPanelSizeStore(defaults: defaults)

        XCTAssertEqual(store.load(), CGSize(width: 360, height: 450))

        store.save(CGSize(width: 320, height: 400))
        let saved = defaults.dictionary(forKey: PinnedPanelSizeStore.defaultsKey) ?? [:]
        XCTAssertEqual(saved["width"] as? Double, 320)
        XCTAssertEqual(saved["height"] as? Double, 400)
        XCTAssertNil(saved["corner"])
        XCTAssertNil(saved["isPinned"])
    }

    func testPinnedSizePersistsAcrossFreshAdapter() {
        let defaults = isolatedDefaults()
        PinnedPanelSizeStore(defaults: defaults).save(
            CGSize(width: 475, height: 625)
        )

        let freshStore = PinnedPanelSizeStore(defaults: defaults)

        XCTAssertEqual(freshStore.load(), CGSize(width: 475, height: 625))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CornerPet.PinnedPanelSizeStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}

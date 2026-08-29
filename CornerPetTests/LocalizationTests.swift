import Foundation
import XCTest

@testable import CornerPet

final class LocalizationTests: XCTestCase {
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

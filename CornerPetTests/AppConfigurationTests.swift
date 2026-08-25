import AppKit
import XCTest

@testable import CornerPet

final class AppConfigurationTests: XCTestCase {
    func testMinimumMacOSMajorVersionIs14() {
        XCTAssertEqual(AppConfiguration.minimumMacOSMajorVersion, 14)
    }

    func testProductNamesAreStable() {
        XCTAssertEqual(AppConfiguration.englishProductName, "CornerPet")
        XCTAssertEqual(AppConfiguration.chineseProductName, "角落灵感箱")
        XCTAssertEqual(AppConfiguration.displayName, "CornerPet / 角落灵感箱")
    }

    func testActivationPolicyIsAccessory() {
        XCTAssertEqual(AppConfiguration.activationPolicy, .accessory)
    }
}

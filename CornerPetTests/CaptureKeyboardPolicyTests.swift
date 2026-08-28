import XCTest

@testable import CornerPet

final class CaptureKeyboardPolicyTests: XCTestCase {
    func testReturnAndKeypadEnterSubmitWithoutShift() {
        XCTAssertEqual(
            CaptureKeyboardPolicy.action(keyCode: 36, isShiftPressed: false),
            .submit
        )
        XCTAssertEqual(
            CaptureKeyboardPolicy.action(keyCode: 76, isShiftPressed: false),
            .submit
        )
    }

    func testShiftReturnAndShiftKeypadEnterInsertNewline() {
        XCTAssertEqual(
            CaptureKeyboardPolicy.action(keyCode: 36, isShiftPressed: true),
            .insertNewline
        )
        XCTAssertEqual(
            CaptureKeyboardPolicy.action(keyCode: 76, isShiftPressed: true),
            .insertNewline
        )
    }

    func testEscapeMapsToEscapeAndOtherKeysPassThrough() {
        XCTAssertEqual(
            CaptureKeyboardPolicy.action(keyCode: 53, isShiftPressed: false),
            .escape
        )
        XCTAssertEqual(
            CaptureKeyboardPolicy.action(keyCode: 51, isShiftPressed: false),
            .passThrough
        )
    }
}

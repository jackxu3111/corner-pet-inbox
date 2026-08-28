import XCTest

@testable import CornerPet

final class PostSubmissionPolicyTests: XCTestCase {
    func testEveryPointerAndPinBranch() {
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: true, isPinned: false),
            .keepOpenAndRefocus
        )
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: false, isPinned: false),
            .closePanel
        )
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: true, isPinned: true),
            .keepOpenAndRefocus
        )
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: false, isPinned: true),
            .keepOpenAndRefocus
        )
    }
}

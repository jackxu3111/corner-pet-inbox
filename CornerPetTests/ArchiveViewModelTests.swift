import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class ArchiveViewModelTests: XCTestCase {
    func testLoadPublishesStoreOrderAndClearsPreviousError() {
        let newer = makeItem(seconds: 20, text: "newer")
        let older = makeItem(seconds: 10, text: "older")
        let store = ArchiveItemStoreStub(fetchResults: [
            .failure(.fetchFailed),
            .success([newer, older])
        ])
        let viewModel = ArchiveViewModel(itemStore: store)

        viewModel.load()
        viewModel.load()

        XCTAssertEqual(viewModel.items, [newer, older])
        XCTAssertNil(viewModel.loadError)
    }

    func testLoadFailureClearsStaleItemsAndShowsRetryableError() {
        let existing = makeItem(seconds: 10, text: "existing")
        let store = ArchiveItemStoreStub(fetchResults: [
            .success([existing]),
            .failure(.fetchFailed)
        ])
        let viewModel = ArchiveViewModel(itemStore: store)
        viewModel.load()

        viewModel.load()

        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(viewModel.loadError, .loadFailed)
    }

    func testRetryLoadsItemsAfterFailure() {
        let recovered = makeItem(seconds: 30, text: "recovered")
        let store = ArchiveItemStoreStub(fetchResults: [
            .failure(.fetchFailed),
            .success([recovered])
        ])
        let viewModel = ArchiveViewModel(itemStore: store)
        viewModel.load()

        viewModel.retryLoad()

        XCTAssertEqual(viewModel.items, [recovered])
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(store.fetchCallCount, 2)
    }

    private func makeItem(
        seconds: TimeInterval,
        text: String
    ) -> IdeaItemSnapshot {
        let date = Date(timeIntervalSince1970: seconds)
        return IdeaItemSnapshot(
            id: UUID(),
            text: text,
            bucket: .archive,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        )
    }
}

private enum ArchiveViewModelTestError: Error {
    case fetchFailed
}

@MainActor
private final class ArchiveItemStoreStub: ArchiveItemStoring {
    private var fetchResults: [Result<[IdeaItemSnapshot], ArchiveViewModelTestError>]
    private(set) var fetchCallCount = 0

    init(fetchResults: [Result<[IdeaItemSnapshot], ArchiveViewModelTestError>]) {
        self.fetchResults = fetchResults
    }

    func fetchArchive() throws -> [IdeaItemSnapshot] {
        fetchCallCount += 1
        guard !fetchResults.isEmpty else { return [] }
        return try fetchResults.removeFirst().get()
    }
}

import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class InboxViewModelTests: XCTestCase {
    func testLoadPublishesStoreOrderAndClearsPreviousError() {
        let newer = makeItem(seconds: 20, text: "newer")
        let older = makeItem(seconds: 10, text: "older")
        let store = InboxItemStoreStub(fetchResults: [
            .failure(.fetchFailed),
            .success([newer, older])
        ])
        let viewModel = InboxViewModel(itemStore: store)

        viewModel.load()
        viewModel.load()

        XCTAssertEqual(viewModel.items, [newer, older])
        XCTAssertNil(viewModel.loadError)
    }

    func testLoadFailureReplacesOnlyListStateWithRetryableError() {
        let existing = makeItem(seconds: 10, text: "existing")
        let store = InboxItemStoreStub(fetchResults: [
            .success([existing]),
            .failure(.fetchFailed)
        ])
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.load()

        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(viewModel.loadError, .loadFailed)
    }

    func testRetryLoadsItemsAfterFailure() {
        let recovered = makeItem(seconds: 30, text: "recovered")
        let store = InboxItemStoreStub(fetchResults: [
            .failure(.fetchFailed),
            .success([recovered])
        ])
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.retryLoad()

        XCTAssertEqual(viewModel.items, [recovered])
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(store.fetchCallCount, 2)
    }

    func testPrependPlacesNewItemAtZeroWithoutRefetch() {
        let existing = makeItem(seconds: 10, text: "existing")
        let incoming = makeItem(seconds: 20, text: "incoming")
        let store = InboxItemStoreStub(fetchResults: [.success([existing])])
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.prepend(incoming)

        XCTAssertEqual(viewModel.items, [incoming, existing])
        XCTAssertEqual(store.fetchCallCount, 1)
    }

    func testPrependSameIDReplacesInsteadOfDuplicatingVisibleRow() {
        let id = UUID()
        let original = makeItem(id: id, seconds: 10, text: "original")
        let replacement = makeItem(id: id, seconds: 20, text: "replacement")
        let store = InboxItemStoreStub(fetchResults: [.success([original])])
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.prepend(replacement)

        XCTAssertEqual(viewModel.items, [replacement])
    }

    func testPrependPreservesNewestFirstOrderForOutOfOrderCallback() {
        let oldest = makeItem(seconds: 10, text: "oldest")
        let middle = makeItem(seconds: 20, text: "middle")
        let newest = makeItem(seconds: 30, text: "newest")
        let viewModel = InboxViewModel(itemStore: InboxItemStoreStub())

        viewModel.prepend(oldest)
        viewModel.prepend(newest)
        viewModel.prepend(middle)

        XCTAssertEqual(viewModel.items, [newest, middle, oldest])
    }

    func testCompleteArchivesThroughStoreThenRemovesVisibleItem() {
        let item = makeItem(seconds: 40, text: "finish me")
        let archivedAt = Date(timeIntervalSince1970: 41)
        let archived = IdeaItemSnapshot(
            id: item.id,
            text: item.text,
            bucket: .archive,
            createdAt: item.createdAt,
            updatedAt: archivedAt,
            movedAt: archivedAt
        )
        let store = InboxItemStoreStub(
            fetchResults: [.success([item])],
            archiveResults: [.success(archived)]
        )
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.complete(item, at: archivedAt)

        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(store.archiveRequests, [.init(id: item.id, date: archivedAt)])
    }

    func testCompleteFailureKeepsOriginalItemVisible() {
        let item = makeItem(seconds: 50, text: "must remain")
        let store = InboxItemStoreStub(
            fetchResults: [.success([item])],
            archiveResults: [.failure(.archiveFailed)]
        )
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.complete(item, at: Date(timeIntervalSince1970: 51))

        XCTAssertEqual(viewModel.items, [item])
        XCTAssertEqual(viewModel.completionErrorItemID, item.id)
    }

    func testCompleteSuccessPublishesUndoOfferAfterArchiveSucceeds() {
        let item = makeItem(seconds: 60, text: "undo me")
        let archived = IdeaItemSnapshot(
            id: item.id,
            text: item.text,
            bucket: .archive,
            createdAt: item.createdAt,
            updatedAt: Date(timeIntervalSince1970: 61),
            movedAt: Date(timeIntervalSince1970: 61)
        )
        let store = InboxLifecycleStoreStub(
            fetchResults: [.success([item])],
            archiveResults: [.success(archived)]
        )
        let controller = ArchiveUndoController(
            itemStore: store,
            scheduler: InboxUndoManualScheduler(),
            clock: { 10.0 }
        )
        let viewModel = InboxViewModel(itemStore: store, archiveUndoController: controller)
        viewModel.load()

        viewModel.complete(item, at: Date(timeIntervalSince1970: 61))

        XCTAssertEqual(viewModel.items, [])
        XCTAssertEqual(viewModel.archiveUndoOffer?.item, archived)
    }

    func testUndoRestoresInboxOrderingThroughViewModelCallback() {
        let older = makeItem(seconds: 70, text: "older")
        let archived = IdeaItemSnapshot(
            id: older.id,
            text: older.text,
            bucket: .archive,
            createdAt: older.createdAt,
            updatedAt: Date(timeIntervalSince1970: 71),
            movedAt: Date(timeIntervalSince1970: 71)
        )
        let restored = IdeaItemSnapshot(
            id: older.id,
            text: older.text,
            bucket: .inbox,
            createdAt: older.createdAt,
            updatedAt: Date(timeIntervalSince1970: 72),
            movedAt: Date(timeIntervalSince1970: 72)
        )
        let store = InboxLifecycleStoreStub(
            fetchResults: [.success([older])],
            archiveResults: [.success(archived)],
            moveResults: [.success(restored)]
        )
        let controller = ArchiveUndoController(
            itemStore: store,
            scheduler: InboxUndoManualScheduler(),
            clock: { 10.0 }
        )
        let viewModel = InboxViewModel(itemStore: store, archiveUndoController: controller)
        viewModel.load()
        viewModel.complete(older, at: Date(timeIntervalSince1970: 71))

        viewModel.undoLastArchive()

        XCTAssertEqual(viewModel.items, [restored])
        XCTAssertNil(viewModel.archiveUndoOffer)
    }

    private func makeItem(
        id: UUID = UUID(),
        seconds: TimeInterval,
        text: String
    ) -> IdeaItemSnapshot {
        let date = Date(timeIntervalSince1970: seconds)
        return IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: .inbox,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        )
    }
}

@MainActor
private final class InboxLifecycleStoreStub: InboxItemStoring, ItemLifecycleStoring {
    private var fetchResults: [Result<[IdeaItemSnapshot], InboxViewModelTestError>]
    private var archiveResults: [Result<IdeaItemSnapshot?, InboxViewModelTestError>]
    private var moveResults: [Result<IdeaItemSnapshot?, InboxViewModelTestError>]

    init(
        fetchResults: [Result<[IdeaItemSnapshot], InboxViewModelTestError>],
        archiveResults: [Result<IdeaItemSnapshot?, InboxViewModelTestError>],
        moveResults: [Result<IdeaItemSnapshot?, InboxViewModelTestError>] = []
    ) {
        self.fetchResults = fetchResults
        self.archiveResults = archiveResults
        self.moveResults = moveResults
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? {
        nil
    }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        guard !fetchResults.isEmpty else { return [] }
        return try fetchResults.removeFirst().get()
    }

    func archiveInboxItem(id: UUID, at date: Date) throws -> IdeaItemSnapshot? {
        guard !archiveResults.isEmpty else { return nil }
        return try archiveResults.removeFirst().get()
    }

    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot] {
        []
    }

    func moveItem(
        id: UUID,
        from source: ItemBucket,
        to destination: ItemBucket,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        guard !moveResults.isEmpty else { return nil }
        return try moveResults.removeFirst().get()
    }

    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        nil
    }

    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool {
        false
    }
}

private enum InboxViewModelTestError: Error {
    case fetchFailed
    case archiveFailed
}

private struct ArchiveRequest: Equatable {
    let id: UUID
    let date: Date
}

@MainActor
private final class InboxItemStoreStub: InboxItemStoring {
    private var fetchResults: [Result<[IdeaItemSnapshot], InboxViewModelTestError>]
    private var archiveResults: [Result<IdeaItemSnapshot?, InboxViewModelTestError>]
    private(set) var fetchCallCount = 0
    private(set) var archiveRequests: [ArchiveRequest] = []

    init(
        fetchResults: [Result<[IdeaItemSnapshot], InboxViewModelTestError>] = [],
        archiveResults: [Result<IdeaItemSnapshot?, InboxViewModelTestError>] = []
    ) {
        self.fetchResults = fetchResults
        self.archiveResults = archiveResults
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? {
        nil
    }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        fetchCallCount += 1
        guard !fetchResults.isEmpty else { return [] }
        return try fetchResults.removeFirst().get()
    }

    func archiveInboxItem(id: UUID, at date: Date) throws -> IdeaItemSnapshot? {
        archiveRequests.append(.init(id: id, date: date))
        guard !archiveResults.isEmpty else { return nil }
        return try archiveResults.removeFirst().get()
    }
}

@MainActor
private final class InboxUndoManualScheduler: HotCornerDeadlineScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> HotCornerCancellation {
        InboxUndoManualToken(operation: operation)
    }
}

@MainActor
private final class InboxUndoManualToken: HotCornerCancellation {
    let operation: @MainActor () -> Void

    init(operation: @escaping @MainActor () -> Void) {
        self.operation = operation
    }

    func cancel() {}
}

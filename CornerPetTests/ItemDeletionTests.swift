import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class ItemDeletionTests: XCTestCase {
    func testDeleteRequestRequiresSecondAction() {
        let item = makeItem(text: "keep until confirmed")
        let store = DeletionStoreStub(inboxResults: [.success([item])])
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()

        viewModel.requestDelete(item)

        XCTAssertEqual(viewModel.pendingDeletion, item)
        XCTAssertEqual(viewModel.items, [item])
        XCTAssertTrue(store.deleteRequests.isEmpty)
    }

    func testDeleteCancellationNeverCallsStore() {
        let item = makeItem(text: "cancel")
        let store = DeletionStoreStub(inboxResults: [.success([item])])
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()
        viewModel.requestDelete(item)

        viewModel.cancelDelete()

        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertEqual(viewModel.items, [item])
        XCTAssertTrue(store.deleteRequests.isEmpty)
    }

    func testConfirmedDeleteRemovesExactlyOneVisibleAndPersistedItem() {
        let first = makeItem(text: "delete me")
        let second = makeItem(text: "keep me")
        let store = DeletionStoreStub(
            inboxResults: [.success([first, second])],
            deleteResults: [.success(true)]
        )
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()
        viewModel.requestDelete(first)

        XCTAssertTrue(viewModel.confirmDelete())

        XCTAssertEqual(viewModel.items, [second])
        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertEqual(store.deleteRequests, [.init(id: first.id, bucket: .inbox)])
    }

    func testDeleteFailureKeepsItemAndShowsError() {
        let item = makeItem(text: "must remain")
        let store = DeletionStoreStub(
            inboxResults: [.success([item])],
            deleteResults: [.failure(.deleteFailed)]
        )
        let viewModel = InboxViewModel(itemStore: store)
        viewModel.load()
        viewModel.requestDelete(item)

        XCTAssertFalse(viewModel.confirmDelete())

        XCTAssertEqual(viewModel.items, [item])
        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertEqual(viewModel.deletionErrorItemID, item.id)
    }

    func testDeleteCancellationAndFailureAlsoKeepFavoritesAndArchiveRows() {
        let archiveItem = makeItem(text: "archived", bucket: .archive)
        let favoriteItem = makeItem(text: "favorite", bucket: .favorite)
        let store = DeletionStoreStub(
            fetchByBucket: [
                .archive: [.success([archiveItem])],
                .favorite: [.success([favoriteItem])]
            ],
            deleteResults: [.failure(.deleteFailed)]
        )
        let archive = ArchiveViewModel(itemStore: store)
        let favorites = FavoritesViewModel(itemStore: store)
        archive.load()
        favorites.load()

        archive.requestDelete(archiveItem)
        archive.cancelDelete()
        favorites.requestDelete(favoriteItem)
        XCTAssertFalse(favorites.confirmDelete())

        XCTAssertEqual(archive.items, [archiveItem])
        XCTAssertEqual(favorites.items, [favoriteItem])
        XCTAssertNil(favorites.pendingDeletion)
        XCTAssertEqual(favorites.deletionErrorItemID, favoriteItem.id)
    }

    func testArchiveDeleteFailureClosesConfirmationAndKeepsErrorState() {
        let item = makeItem(text: "archive failure", bucket: .archive)
        let store = DeletionStoreStub(
            fetchByBucket: [.archive: [.success([item])]],
            deleteResults: [.failure(.deleteFailed)]
        )
        let archive = ArchiveViewModel(itemStore: store)
        archive.load()

        archive.requestDelete(item)

        XCTAssertFalse(archive.confirmDelete())
        XCTAssertEqual(archive.items, [item])
        XCTAssertNil(archive.pendingDeletion)
        XCTAssertEqual(archive.deletionErrorItemID, item.id)
    }

    func testFavoriteDeleteFailureClosesConfirmationAndKeepsErrorState() {
        let item = makeItem(text: "favorite failure", bucket: .favorite)
        let store = DeletionStoreStub(
            fetchByBucket: [.favorite: [.success([item])]],
            deleteResults: [.failure(.deleteFailed)]
        )
        let favorites = FavoritesViewModel(itemStore: store)
        favorites.load()

        favorites.requestDelete(item)

        XCTAssertFalse(favorites.confirmDelete())
        XCTAssertEqual(favorites.items, [item])
        XCTAssertNil(favorites.pendingDeletion)
        XCTAssertEqual(favorites.deletionErrorItemID, item.id)
    }

    func testDeleteIsDisabledDuringActiveEdit() {
        let item = makeItem(text: "editing")
        let store = DeletionStoreStub(inboxResults: [.success([item])])
        let editor = ItemEditViewModel(itemStore: store)
        let viewModel = InboxViewModel(itemStore: store, editViewModel: editor)
        viewModel.load()
        XCTAssertTrue(editor.beginEditing(item))

        viewModel.requestDelete(item)

        XCTAssertNil(viewModel.pendingDeletion)
        XCTAssertTrue(store.deleteRequests.isEmpty)
    }

    private func makeItem(
        id: UUID = UUID(),
        text: String,
        bucket: ItemBucket = .inbox
    ) -> IdeaItemSnapshot {
        let date = Date(timeIntervalSince1970: 1)
        return IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: bucket,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        )
    }
}

@MainActor
private final class DeletionStoreStub: InboxItemStoring, ArchiveItemStoring, ItemLifecycleStoring {
    struct DeleteRequest: Equatable {
        let id: UUID
        let bucket: ItemBucket
    }

    private var inboxResults: [Result<[IdeaItemSnapshot], DeletionStoreError>]
    private var archiveResults: [Result<[IdeaItemSnapshot], DeletionStoreError>]
    private var fetchByBucket: [ItemBucket: [Result<[IdeaItemSnapshot], DeletionStoreError>]]
    private var deleteResults: [Result<Bool, DeletionStoreError>]
    private(set) var deleteRequests: [DeleteRequest] = []

    init(
        inboxResults: [Result<[IdeaItemSnapshot], DeletionStoreError>] = [],
        archiveResults: [Result<[IdeaItemSnapshot], DeletionStoreError>] = [],
        fetchByBucket: [ItemBucket: [Result<[IdeaItemSnapshot], DeletionStoreError>]] = [:],
        deleteResults: [Result<Bool, DeletionStoreError>] = []
    ) {
        self.inboxResults = inboxResults
        self.archiveResults = archiveResults
        self.fetchByBucket = fetchByBucket
        self.deleteResults = deleteResults
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? { nil }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        guard !inboxResults.isEmpty else { return [] }
        return try inboxResults.removeFirst().get()
    }

    func fetchArchive() throws -> [IdeaItemSnapshot] {
        guard !archiveResults.isEmpty else { return [] }
        return try archiveResults.removeFirst().get()
    }

    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot] {
        guard var results = fetchByBucket[bucket], !results.isEmpty else { return [] }
        let result = results.removeFirst()
        fetchByBucket[bucket] = results
        return try result.get()
    }

    func archiveInboxItem(id: UUID, at date: Date) throws -> IdeaItemSnapshot? { nil }

    func moveItem(
        id: UUID,
        from source: ItemBucket,
        to destination: ItemBucket,
        at date: Date
    ) throws -> IdeaItemSnapshot? { nil }

    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot? { nil }

    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool {
        deleteRequests.append(.init(id: id, bucket: expectedBucket))
        guard !deleteResults.isEmpty else { return false }
        return try deleteResults.removeFirst().get()
    }
}

private enum DeletionStoreError: Error {
    case deleteFailed
    case fetchFailed
}

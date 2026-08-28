import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testCommandFRouteRequestsFocusForEachLibrarySearch() {
        var archiveFocused = false
        var favoritesFocused = false

        LibrarySearchFocusRouting.requestFocus { archiveFocused = $0 }
        LibrarySearchFocusRouting.requestFocus { favoritesFocused = $0 }

        XCTAssertTrue(archiveFocused)
        XCTAssertTrue(favoritesFocused)
    }

    func testSearchUsesLocalizedStandardContainsForChineseAndCaseDiacritics() {
        let items = [
            makeItem(text: "给猫咪买咖啡", bucket: .archive),
            makeItem(text: "Café rendezvous", bucket: .archive),
            makeItem(text: "Unrelated", bucket: .archive)
        ]

        XCTAssertEqual(
            LibrarySearch.filter(items, query: "咖啡").map(\.text),
            ["给猫咪买咖啡"]
        )
        XCTAssertEqual(
            LibrarySearch.filter(items, query: "CAFE").map(\.text),
            ["Café rendezvous"]
        )
    }

    func testEmptySearchReturnsAllSourceItemsAfterPriorFiltering() {
        let source = [
            makeItem(text: "alpha", bucket: .favorite),
            makeItem(text: "beta", bucket: .favorite)
        ]
        let store = LibraryLifecycleStoreStub(fetchByBucket: [.favorite: .success(source)])
        let viewModel = FavoritesViewModel(itemStore: store)

        viewModel.load()
        viewModel.search("alpha")
        XCTAssertEqual(viewModel.items.map(\.text), ["alpha"])

        viewModel.search("")

        XCTAssertEqual(viewModel.allItems, source)
        XCTAssertEqual(viewModel.items, source)
    }

    func testFavoriteSuccessRemovesInboxAndAppearsInFavorites() {
        let item = makeItem(text: "move me", bucket: .inbox)
        let favorite = item.withBucket(.favorite, movedAt: 11)
        let store = LibraryLifecycleStoreStub(
            inboxResults: [.success([item])],
            moveResults: [.success(favorite)]
        )
        let inbox = InboxViewModel(itemStore: store)
        let favorites = FavoritesViewModel(itemStore: store)
        inbox.onItemFavorited = { favorites.upsert($0) }
        inbox.load()

        inbox.favorite(item, at: Date(timeIntervalSince1970: 11))

        XCTAssertEqual(inbox.items, [])
        XCTAssertEqual(favorites.items, [favorite])
        XCTAssertEqual(store.moveRequests, [
            .init(id: item.id, from: .inbox, to: .favorite, date: Date(timeIntervalSince1970: 11))
        ])
    }

    func testFavoriteFailureLeavesInboxRowAndShowsError() {
        let item = makeItem(text: "keep me", bucket: .inbox)
        let store = LibraryLifecycleStoreStub(
            inboxResults: [.success([item])],
            moveResults: [.failure(.moveFailed)]
        )
        let inbox = InboxViewModel(itemStore: store)
        inbox.load()

        inbox.favorite(item, at: Date(timeIntervalSince1970: 12))

        XCTAssertEqual(inbox.items, [item])
        XCTAssertEqual(inbox.favoriteErrorItemID, item.id)
    }

    func testUnfavoriteReturnsItemToInbox() {
        let item = makeItem(text: "restore me", bucket: .favorite)
        let restored = item.withBucket(.inbox, movedAt: 21)
        let store = LibraryLifecycleStoreStub(
            fetchByBucket: [.favorite: .success([item])],
            moveResults: [.success(restored)]
        )
        let favorites = FavoritesViewModel(itemStore: store)
        var restoredInInbox: [IdeaItemSnapshot] = []
        favorites.onItemUnfavorited = { restoredInInbox.append($0) }
        favorites.load()

        favorites.unfavorite(item, at: Date(timeIntervalSince1970: 21))

        XCTAssertEqual(favorites.items, [])
        XCTAssertEqual(restoredInInbox, [restored])
        XCTAssertEqual(store.moveRequests, [
            .init(id: item.id, from: .favorite, to: .inbox, date: Date(timeIntervalSince1970: 21))
        ])
    }

    func testArchiveAndFavoritesNeverLeakEachOthersItems() {
        let archived = makeItem(text: "archived", bucket: .archive)
        let favorite = makeItem(text: "favorite", bucket: .favorite)
        let store = LibraryLifecycleStoreStub(
            fetchByBucket: [
                .archive: .success([archived]),
                .favorite: .success([favorite])
            ]
        )
        let archive = ArchiveViewModel(itemStore: store)
        let favorites = FavoritesViewModel(itemStore: store)

        archive.load()
        favorites.load()

        XCTAssertEqual(archive.items, [archived])
        XCTAssertEqual(favorites.items, [favorite])
        XCTAssertFalse(archive.items.contains(favorite))
        XCTAssertFalse(favorites.items.contains(archived))
    }

    func testSearchQueryClearingAfterLoadRetryRestoresNewSource() {
        let first = makeItem(text: "first", bucket: .archive)
        let second = makeItem(text: "second", bucket: .archive)
        let store = LibraryLifecycleStoreStub(
            fetchQueues: [.archive: [.failure(.fetchFailed), .success([first, second])]]
        )
        let archive = ArchiveViewModel(itemStore: store)

        archive.load()
        archive.search("first")
        archive.retryLoad()
        archive.search("")

        XCTAssertEqual(archive.allItems, [first, second])
        XCTAssertEqual(archive.items, [first, second])
        XCTAssertNil(archive.loadError)
    }

    private func makeItem(
        id: UUID = UUID(),
        text: String,
        bucket: ItemBucket,
        movedAt: TimeInterval = 1
    ) -> IdeaItemSnapshot {
        let created = Date(timeIntervalSince1970: 0)
        let moved = Date(timeIntervalSince1970: movedAt)
        return IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: bucket,
            createdAt: created,
            updatedAt: moved,
            movedAt: moved
        )
    }
}

private extension IdeaItemSnapshot {
    func withBucket(_ bucket: ItemBucket, movedAt: TimeInterval) -> IdeaItemSnapshot {
        let moved = Date(timeIntervalSince1970: movedAt)
        return IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: bucket,
            createdAt: createdAt,
            updatedAt: moved,
            movedAt: moved
        )
    }
}

@MainActor
private final class LibraryLifecycleStoreStub: InboxItemStoring, ArchiveItemStoring, ItemLifecycleStoring {
    struct MoveRequest: Equatable {
        let id: UUID
        let from: ItemBucket
        let to: ItemBucket
        let date: Date
    }

    private var inboxResults: [Result<[IdeaItemSnapshot], LibraryStoreError>]
    private var archiveResults: [Result<[IdeaItemSnapshot], LibraryStoreError>]
    private var fetchByBucket: [ItemBucket: [Result<[IdeaItemSnapshot], LibraryStoreError>]]
    private var moveResults: [Result<IdeaItemSnapshot?, LibraryStoreError>]
    private(set) var moveRequests: [MoveRequest] = []

    init(
        inboxResults: [Result<[IdeaItemSnapshot], LibraryStoreError>] = [],
        archiveResults: [Result<[IdeaItemSnapshot], LibraryStoreError>] = [],
        fetchByBucket: [ItemBucket: Result<[IdeaItemSnapshot], LibraryStoreError>] = [:],
        fetchQueues: [ItemBucket: [Result<[IdeaItemSnapshot], LibraryStoreError>]] = [:],
        moveResults: [Result<IdeaItemSnapshot?, LibraryStoreError>] = []
    ) {
        self.inboxResults = inboxResults
        self.archiveResults = archiveResults
        self.fetchByBucket = fetchQueues.merging(fetchByBucket.mapValues { [$0] }) { queues, _ in queues }
        self.moveResults = moveResults
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
    ) throws -> IdeaItemSnapshot? {
        moveRequests.append(.init(id: id, from: source, to: destination, date: date))
        guard !moveResults.isEmpty else { return nil }
        return try moveResults.removeFirst().get()
    }

    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot? { nil }

    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool { false }
}

private enum LibraryStoreError: Error {
    case fetchFailed
    case moveFailed
}

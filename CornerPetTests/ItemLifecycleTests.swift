import Foundation
import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class ItemLifecycleTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case writeFailed
    }

    func testFetchItemsFiltersBucketAndSortsMovedBucketsNewestFirst() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let archiveOlderID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let archiveNewerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))
        let favoriteID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000103"))
        let inboxID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000104"))
        let createdAt = Date(timeIntervalSince1970: 100)
        let olderMove = Date(timeIntervalSince1970: 101)
        let newerMove = Date(timeIntervalSince1970: 102)
        context.insert(IdeaItem(
            id: archiveOlderID,
            text: "archive older",
            bucket: .archive,
            createdAt: createdAt,
            updatedAt: olderMove,
            movedAt: olderMove
        ))
        context.insert(IdeaItem(
            id: archiveNewerID,
            text: "archive newer",
            bucket: .archive,
            createdAt: createdAt,
            updatedAt: newerMove,
            movedAt: newerMove
        ))
        context.insert(IdeaItem(
            id: favoriteID,
            text: "favorite",
            bucket: .favorite,
            createdAt: createdAt,
            updatedAt: newerMove,
            movedAt: newerMove
        ))
        context.insert(IdeaItem(
            id: inboxID,
            text: "inbox",
            bucket: .inbox,
            createdAt: newerMove,
            updatedAt: newerMove,
            movedAt: olderMove
        ))
        try context.save()
        let store = ItemStore(context: context)

        XCTAssertEqual(try store.fetchItems(in: .archive).map(\.id), [archiveNewerID, archiveOlderID])
        XCTAssertEqual(try store.fetchItems(in: .favorite).map(\.id), [favoriteID])
        XCTAssertEqual(try store.fetchItems(in: .inbox).map(\.id), [inboxID])
    }

    func testMoveInboxToFavoriteAndFavoriteBackToInboxPreservesCreatedAt() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = ItemStore(context: context)
        let createdAt = Date(timeIntervalSince1970: 110)
        let favoriteAt = Date(timeIntervalSince1970: 111)
        let inboxAt = Date(timeIntervalSince1970: 112)
        let item = try XCTUnwrap(store.createInboxItem(text: "move me", at: createdAt))

        let favorite = try XCTUnwrap(try store.moveItem(
            id: item.id,
            from: .inbox,
            to: .favorite,
            at: favoriteAt
        ))
        XCTAssertEqual(favorite.bucket, .favorite)
        XCTAssertEqual(favorite.createdAt, createdAt)
        XCTAssertEqual(favorite.updatedAt, favoriteAt)
        XCTAssertEqual(favorite.movedAt, favoriteAt)

        let inbox = try XCTUnwrap(try store.moveItem(
            id: item.id,
            from: .favorite,
            to: .inbox,
            at: inboxAt
        ))
        XCTAssertEqual(inbox.bucket, .inbox)
        XCTAssertEqual(inbox.createdAt, createdAt)
        XCTAssertEqual(inbox.updatedAt, inboxAt)
        XCTAssertEqual(inbox.movedAt, inboxAt)
    }

    func testMoveArchiveBackToInboxPersistsAcrossFreshContext() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = ItemStore(context: context)
        let item = try XCTUnwrap(store.createInboxItem(text: "undo me", at: Date(timeIntervalSince1970: 120)))
        _ = try XCTUnwrap(try store.archiveInboxItem(id: item.id, at: Date(timeIntervalSince1970: 121)))

        _ = try XCTUnwrap(try store.moveItem(
            id: item.id,
            from: .archive,
            to: .inbox,
            at: Date(timeIntervalSince1970: 122)
        ))

        let freshContext = ModelContext(container)
        let freshStore = ItemStore(context: freshContext)
        XCTAssertEqual(try freshStore.fetchInbox().map(\.id), [item.id])
        XCTAssertEqual(try freshStore.fetchArchive(), [])
    }

    func testMoveRejectsWrongExpectedSource() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = ItemStore(context: context)
        let item = try XCTUnwrap(store.createInboxItem(text: "source guard", at: Date(timeIntervalSince1970: 130)))
        _ = try XCTUnwrap(try store.archiveInboxItem(id: item.id, at: Date(timeIntervalSince1970: 131)))

        XCTAssertNil(try store.moveItem(
            id: item.id,
            from: .inbox,
            to: .favorite,
            at: Date(timeIntervalSince1970: 132)
        ))
        XCTAssertEqual(try store.fetchArchive().map(\.id), [item.id])
    }

    func testUpdateTextPreservesCreatedAtAndMovedAtButChangesUpdatedAt() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = ItemStore(context: context)
        let createdAt = Date(timeIntervalSince1970: 140)
        let archivedAt = Date(timeIntervalSince1970: 141)
        let updatedAt = Date(timeIntervalSince1970: 142)
        let item = try XCTUnwrap(store.createInboxItem(text: "before", at: createdAt))
        _ = try XCTUnwrap(try store.archiveInboxItem(id: item.id, at: archivedAt))

        let updated = try XCTUnwrap(try store.updateItemText(
            id: item.id,
            expectedBucket: .archive,
            text: " exact edited text ",
            at: updatedAt
        ))
        XCTAssertEqual(updated.text, " exact edited text ")
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertEqual(updated.movedAt, archivedAt)
        XCTAssertEqual(updated.updatedAt, updatedAt)
    }

    func testFailedMoveRollsBackExactBucketAndTimestamps() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let reliableStore = ItemStore(context: context)
        let createdAt = Date(timeIntervalSince1970: 150)
        let item = try XCTUnwrap(reliableStore.createInboxItem(text: "move rollback", at: createdAt))
        let failingStore = ItemStore(context: context, save: { _ in throw TestError.writeFailed })

        XCTAssertThrowsError(try failingStore.moveItem(
            id: item.id,
            from: .inbox,
            to: .archive,
            at: Date(timeIntervalSince1970: 151)
        )) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        let freshContext = ModelContext(container)
        let freshStore = ItemStore(context: freshContext)
        XCTAssertEqual(try freshStore.fetchInbox(), [item])
        XCTAssertEqual(try freshStore.fetchArchive(), [])
    }

    func testFailedUpdateRollsBackExactOldTextAndTimestamps() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let reliableStore = ItemStore(context: context)
        let createdAt = Date(timeIntervalSince1970: 160)
        let item = try XCTUnwrap(reliableStore.createInboxItem(text: "old exact text", at: createdAt))
        let failingStore = ItemStore(context: context, save: { _ in throw TestError.writeFailed })

        XCTAssertThrowsError(try failingStore.updateItemText(
            id: item.id,
            expectedBucket: .inbox,
            text: "new text that is not durable",
            at: Date(timeIntervalSince1970: 161)
        )) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        let freshContext = ModelContext(container)
        let persisted = try XCTUnwrap(freshContext.fetch(FetchDescriptor<IdeaItem>()).first)
        XCTAssertEqual(persisted.text, "old exact text")
        XCTAssertEqual(persisted.createdAt, createdAt)
        XCTAssertEqual(persisted.updatedAt, createdAt)
        XCTAssertEqual(persisted.movedAt, createdAt)
    }

    func testPermanentDeleteRemovesOnlyConfirmedID() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = ItemStore(context: context)
        let first = try XCTUnwrap(store.createInboxItem(text: "keep", at: Date(timeIntervalSince1970: 170)))
        let second = try XCTUnwrap(store.createInboxItem(text: "remove", at: Date(timeIntervalSince1970: 171)))

        XCTAssertTrue(try store.deletePermanently(id: second.id, expectedBucket: .inbox))

        let freshContext = ModelContext(container)
        let freshStore = ItemStore(context: freshContext)
        XCTAssertEqual(try freshStore.fetchInbox().map(\.id), [first.id])
    }

    func testFailedDeleteKeepsItemInOriginalBucketInFreshContext() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let reliableStore = ItemStore(context: context)
        let item = try XCTUnwrap(reliableStore.createInboxItem(text: "must remain", at: Date(timeIntervalSince1970: 180)))
        let failingStore = ItemStore(context: context, save: { _ in throw TestError.writeFailed })

        XCTAssertThrowsError(try failingStore.deletePermanently(id: item.id, expectedBucket: .inbox)) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        let freshContext = ModelContext(container)
        XCTAssertEqual(try ItemStore(context: freshContext).fetchInbox(), [item])
    }
}

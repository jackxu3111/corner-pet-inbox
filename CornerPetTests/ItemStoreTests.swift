import Foundation
import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class ItemStoreTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case writeFailed
    }

    func testWhitespaceOnlyCaptureReturnsNilAndCreatesNoItem() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let store = ItemStore(context: context)

        let result = try store.createInboxItem(
            text: " \t\n  ",
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(result)
        XCTAssertEqual(try context.fetch(FetchDescriptor<IdeaItem>()).count, 0)
    }

    func testCreateTrimsOnlyLeadingAndTrailingWhitespace() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let store = ItemStore(context: context)
        let date = Date(timeIntervalSince1970: 110)

        let item = try XCTUnwrap(store.createInboxItem(
            text: " \n  first \t middle\nsecond  \n ",
            at: date
        ))

        XCTAssertEqual(item.text, "first \t middle\nsecond")
        XCTAssertEqual(item.bucket, .inbox)
        XCTAssertEqual(item.createdAt, date)
        XCTAssertEqual(item.updatedAt, date)
        XCTAssertEqual(item.movedAt, date)
    }

    func testDuplicateTextCreatesDistinctItems() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let store = ItemStore(context: context)
        let firstDate = Date(timeIntervalSince1970: 120)
        let secondDate = Date(timeIntervalSince1970: 121)

        let first = try XCTUnwrap(store.createInboxItem(text: "same", at: firstDate))
        let second = try XCTUnwrap(store.createInboxItem(text: "same", at: secondDate))

        XCTAssertEqual(first.text, second.text)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.fetchInbox().map(\.id), [second.id, first.id])
    }

    func testFetchInboxSortsCreatedAtNewestFirst() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let oldestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let firstNewestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondNewestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let oldDate = Date(timeIntervalSince1970: 130)
        let newDate = Date(timeIntervalSince1970: 131)
        context.insert(IdeaItem(
            id: oldestID,
            text: "oldest",
            createdAt: oldDate,
            updatedAt: oldDate,
            movedAt: oldDate
        ))
        context.insert(IdeaItem(
            id: secondNewestID,
            text: "second tie",
            createdAt: newDate,
            updatedAt: newDate,
            movedAt: newDate
        ))
        context.insert(IdeaItem(
            id: firstNewestID,
            text: "first tie",
            createdAt: newDate,
            updatedAt: newDate,
            movedAt: newDate
        ))
        try context.save()
        let store = ItemStore(context: context)

        XCTAssertEqual(
            try store.fetchInbox().map(\.id),
            [firstNewestID, secondNewestID, oldestID]
        )
    }

    func testFetchInboxExcludesArchiveAndFavoriteBuckets() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let inboxID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let archiveID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let favoriteID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let date = Date(timeIntervalSince1970: 140)
        context.insert(IdeaItem(
            id: inboxID,
            text: "inbox",
            bucket: .inbox,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        ))
        context.insert(IdeaItem(
            id: archiveID,
            text: "archive",
            bucket: .archive,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        ))
        context.insert(IdeaItem(
            id: favoriteID,
            text: "favorite",
            bucket: .favorite,
            createdAt: date,
            updatedAt: date,
            movedAt: date
        ))
        try context.save()
        let store = ItemStore(context: context)

        XCTAssertEqual(try store.fetchInbox().map(\.id), [inboxID])
    }

    func testFetchArchiveReturnsOnlyArchivedItemsNewestMoveFirst() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let olderArchiveID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000020")
        )
        let newerArchiveID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000021")
        )
        let inboxID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000022")
        )
        let createdAt = Date(timeIntervalSince1970: 140)
        let olderMove = Date(timeIntervalSince1970: 141)
        let newerMove = Date(timeIntervalSince1970: 142)
        context.insert(IdeaItem(
            id: olderArchiveID,
            text: "older archive",
            bucket: .archive,
            createdAt: createdAt,
            updatedAt: olderMove,
            movedAt: olderMove
        ))
        context.insert(IdeaItem(
            id: newerArchiveID,
            text: "newer archive",
            bucket: .archive,
            createdAt: createdAt,
            updatedAt: newerMove,
            movedAt: newerMove
        ))
        context.insert(IdeaItem(
            id: inboxID,
            text: "still inbox",
            bucket: .inbox,
            createdAt: createdAt,
            updatedAt: newerMove,
            movedAt: newerMove
        ))
        try context.save()
        let store = ItemStore(context: context)

        XCTAssertEqual(
            try store.fetchArchive().map(\.id),
            [newerArchiveID, olderArchiveID]
        )
    }

    func testArchiveInboxItemPersistsArchiveAndRemovesItFromInbox() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let store = ItemStore(context: context)
        let createdAt = Date(timeIntervalSince1970: 145)
        let archivedAt = Date(timeIntervalSince1970: 146)
        let item = try XCTUnwrap(store.createInboxItem(text: "finish me", at: createdAt))

        let archived = try XCTUnwrap(store.archiveInboxItem(id: item.id, at: archivedAt))

        XCTAssertEqual(archived.bucket, .archive)
        XCTAssertEqual(archived.updatedAt, archivedAt)
        XCTAssertEqual(archived.movedAt, archivedAt)
        XCTAssertEqual(try store.fetchInbox(), [])

        let freshContext = ModelContext(container)
        let persisted = try XCTUnwrap(freshContext.fetch(FetchDescriptor<IdeaItem>()).first)
        XCTAssertEqual(persisted.bucket, .archive)
        XCTAssertEqual(persisted.updatedAt, archivedAt)
        XCTAssertEqual(persisted.movedAt, archivedAt)
    }

    func testFailedArchiveKeepsOriginalItemInInbox() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let reliableStore = ItemStore(context: context)
        let createdAt = Date(timeIntervalSince1970: 147)
        let item = try XCTUnwrap(reliableStore.createInboxItem(text: "must survive", at: createdAt))
        let failingStore = ItemStore(
            context: context,
            save: { _ in throw TestError.writeFailed }
        )

        XCTAssertThrowsError(
            try failingStore.archiveInboxItem(
                id: item.id,
                at: Date(timeIntervalSince1970: 148)
            )
        ) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        XCTAssertEqual(try failingStore.fetchInbox(), [item])
        let freshContext = ModelContext(container)
        XCTAssertEqual(try ItemStore(context: freshContext).fetchInbox(), [item])
    }

    func testFailedSaveThrowsAndDoesNotReportSuccessfulSnapshot() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let draftDate = Date(timeIntervalSince1970: 150)
        context.insert(Draft(text: "must survive", updatedAt: draftDate))
        try context.save()
        let store = ItemStore(
            context: context,
            save: { _ in throw TestError.writeFailed }
        )

        XCTAssertThrowsError(try store.createInboxItem(
            text: "not durable",
            at: Date(timeIntervalSince1970: 151)
        )) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        XCTAssertEqual(try context.fetch(FetchDescriptor<IdeaItem>()).count, 0)
        let freshContext = ModelContext(container)
        XCTAssertEqual(try freshContext.fetch(FetchDescriptor<IdeaItem>()).count, 0)
        XCTAssertEqual(
            try freshContext.fetch(FetchDescriptor<Draft>()).first?.snapshot,
            DraftSnapshot(text: "must survive", updatedAt: draftDate)
        )
    }
}

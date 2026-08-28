import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class ArchiveUndoControllerTests: XCTestCase {
    private enum TestError: Error {
        case restoreFailed
    }

    func testSuccessfulCompletionPublishesUndoForExactlyFiveSeconds() {
        var now = 10.0
        let scheduler = ArchiveUndoManualScheduler()
        let controller = ArchiveUndoController(
            itemStore: ArchiveUndoStoreStub(),
            scheduler: scheduler,
            clock: { now }
        )
        let archived = makeItem(text: "archived")

        controller.publish(archived)

        XCTAssertEqual(controller.offer?.item, archived)
        XCTAssertEqual(controller.offer?.generation, 1)
        XCTAssertEqual(controller.offer?.expiresAt ?? -1, 15.0, accuracy: 0.000001)
        XCTAssertEqual(scheduler.scheduledDelays, [5.0])

        now = 14.999
        scheduler.fire(0)
        XCTAssertNotNil(controller.offer)

        now = 15.0
        scheduler.fire(0)
        XCTAssertNil(controller.offer)
    }

    func testUndoMovesArchivedItemBackAndCancelsExpiry() {
        let scheduler = ArchiveUndoManualScheduler()
        let store = ArchiveUndoStoreStub(moveResult: .success(makeItem(text: "restored", bucket: .inbox)))
        let controller = ArchiveUndoController(
            itemStore: store,
            scheduler: scheduler,
            clock: { 20.0 },
            dateProvider: { Date(timeIntervalSince1970: 20.0) }
        )
        let archived = makeItem(text: "restored")
        var restored: IdeaItemSnapshot?
        controller.onUndoSucceeded = { restored = $0 }
        controller.publish(archived)

        controller.undo()

        XCTAssertEqual(store.moveRequests, [
            .init(id: archived.id, from: .archive, to: .inbox, date: Date(timeIntervalSince1970: 20.0))
        ])
        XCTAssertEqual(restored?.bucket, .inbox)
        XCTAssertNil(controller.offer)
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertNil(controller.error)
    }

    func testStaleExpiryCannotRemoveReplacementOffer() {
        var now = 30.0
        let scheduler = ArchiveUndoManualScheduler()
        let controller = ArchiveUndoController(
            itemStore: ArchiveUndoStoreStub(),
            scheduler: scheduler,
            clock: { now }
        )
        let first = makeItem(text: "first")
        let second = makeItem(text: "second")
        controller.publish(first)
        controller.publish(second)

        now = 35.0
        scheduler.fire(0)

        XCTAssertEqual(controller.offer?.item, second)
        XCTAssertFalse(scheduler.tokens[1].isCancelled)
    }

    func testUndoFailureKeepsOfferAndDoesNotClaimInboxRestore() {
        let scheduler = ArchiveUndoManualScheduler()
        let store = ArchiveUndoStoreStub(moveResult: .failure(TestError.restoreFailed))
        let controller = ArchiveUndoController(
            itemStore: store,
            scheduler: scheduler,
            clock: { 40.0 }
        )
        let archived = makeItem(text: "still archived")
        controller.publish(archived)

        controller.undo()

        XCTAssertEqual(controller.offer?.item, archived)
        XCTAssertEqual(controller.error, .restoreFailed)
        XCTAssertNil(store.restoredItem)
    }

    private func makeItem(
        id: UUID = UUID(),
        text: String,
        bucket: ItemBucket = .archive
    ) -> IdeaItemSnapshot {
        let date = Date(timeIntervalSince1970: 5)
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
private final class ArchiveUndoManualScheduler: HotCornerDeadlineScheduling {
    final class Token: HotCornerCancellation {
        let operation: @MainActor () -> Void
        private(set) var isCancelled = false

        init(operation: @escaping @MainActor () -> Void) {
            self.operation = operation
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var tokens: [Token] = []

    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> HotCornerCancellation {
        scheduledDelays.append(delay)
        let token = Token(operation: operation)
        tokens.append(token)
        return token
    }

    func fire(_ index: Int) {
        tokens[index].operation()
    }
}

@MainActor
private final class ArchiveUndoStoreStub: ItemLifecycleStoring {
    struct MoveRequest: Equatable {
        let id: UUID
        let from: ItemBucket
        let to: ItemBucket
        let date: Date
    }

    var moveResult: Result<IdeaItemSnapshot?, Error>
    private(set) var moveRequests: [MoveRequest] = []
    private(set) var restoredItem: IdeaItemSnapshot?

    init(moveResult: Result<IdeaItemSnapshot?, Error> = .success(nil)) {
        self.moveResult = moveResult
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? {
        nil
    }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        []
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
        moveRequests.append(.init(id: id, from: source, to: destination, date: date))
        let result = try moveResult.get()
        restoredItem = result
        return result
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

import Foundation
import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class DraftStoreTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case fetchFailed
        case writeFailed
    }

    func testRestoreCreatesAndReusesExactlyOneEmptyDraft() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let store = DraftStore(context: context, scheduler: ManualDraftWriteScheduler())

        let first = try store.restore()
        let second = try store.restore()

        XCTAssertEqual(first, DraftSnapshot(text: "", updatedAt: .distantPast))
        XCTAssertEqual(second, first)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
    }

    func testFailedInitialRestoreRollsBackAndRetryCreatesDurableDraft() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        var shouldFail = true
        let store = DraftStore(
            context: context,
            scheduler: ManualDraftWriteScheduler(),
            save: { context in
                if shouldFail {
                    shouldFail = false
                    throw TestError.writeFailed
                }
                try context.save()
            }
        )
        var reportedErrors: [TestError] = []
        store.onWriteFailure = { error in
            if let error = error as? TestError {
                reportedErrors.append(error)
            }
        }

        XCTAssertThrowsError(try store.restore()) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 0)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).count,
            0
        )
        XCTAssertEqual(reportedErrors, [.writeFailed])

        XCTAssertEqual(
            try store.restore(),
            DraftSnapshot(text: "", updatedAt: .distantPast)
        )
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).count,
            1
        )
        XCTAssertEqual(reportedErrors, [.writeFailed])
    }

    func testStageDebouncesAndOnlyLatestTextIsFlushed() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let scheduler = ManualDraftWriteScheduler()
        let store = DraftStore(context: context, scheduler: scheduler, debounce: 0.250)
        _ = try store.restore()
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 11)

        store.stage(text: "first", updatedAt: firstDate)
        store.stage(text: "second", updatedAt: secondDate)

        XCTAssertEqual(scheduler.tokens.count, 2)
        XCTAssertEqual(scheduler.tokens.map(\.delay), [0.250, 0.250])
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertFalse(scheduler.tokens[1].isCancelled)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).first?.text, "")
        XCTAssertEqual(try store.restore(), DraftSnapshot(text: "second", updatedAt: secondDate))

        scheduler.fire(1)

        XCTAssertEqual(try store.restore(), DraftSnapshot(text: "second", updatedAt: secondDate))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).first?.text, "second")
    }

    func testExplicitFlushPersistsImmediatelyAndCancelsPendingWrite() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let scheduler = ManualDraftWriteScheduler()
        let store = DraftStore(context: context, scheduler: scheduler)
        let date = Date(timeIntervalSince1970: 20)
        store.stage(text: "flush now", updatedAt: date)

        try store.flush()

        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertEqual(try store.restore(), DraftSnapshot(text: "flush now", updatedAt: date))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
    }

    func testWriteSuccessNotificationFiresOnlyAfterSuccessfulPersistence() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let scheduler = ManualDraftWriteScheduler()
        var events: [String] = []
        let store = DraftStore(
            context: context,
            scheduler: scheduler,
            save: { context in
                events.append("save")
                try context.save()
            }
        )
        store.onWriteSuccess = {
            events.append("success")
        }

        try store.flush()
        XCTAssertEqual(events, [])

        store.stage(text: "persist me", updatedAt: Date(timeIntervalSince1970: 25))
        XCTAssertEqual(events, [])

        scheduler.fire(0)

        XCTAssertEqual(events, ["save", "success"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).first?.text, "persist me")
    }

    func testSuccessCallbackCanStageNextDraftWithoutCompletedFlushClearingIt() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let scheduler = ManualDraftWriteScheduler()
        let store = DraftStore(context: context, scheduler: scheduler)
        let first = DraftSnapshot(
            text: "first draft",
            updatedAt: Date(timeIntervalSince1970: 27)
        )
        let next = DraftSnapshot(
            text: "next draft",
            updatedAt: Date(timeIntervalSince1970: 28)
        )
        store.stage(text: first.text, updatedAt: first.updatedAt)
        var successCount = 0
        store.onWriteSuccess = {
            successCount += 1
            if successCount == 1 {
                store.stage(text: next.text, updatedAt: next.updatedAt)
            }
        }

        try store.flush()

        XCTAssertEqual(try store.restore(), next)

        try store.flush()

        XCTAssertEqual(try store.restore(), next)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.snapshot,
            next
        )
    }

    func testFailedWriteDoesNotNotifySuccess() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let scheduler = ManualDraftWriteScheduler()
        let store = DraftStore(
            context: context,
            scheduler: scheduler,
            save: { _ in throw TestError.writeFailed }
        )
        var successCount = 0
        store.onWriteSuccess = {
            successCount += 1
        }
        store.stage(text: "still pending", updatedAt: Date(timeIntervalSince1970: 26))

        scheduler.fire(0)

        XCTAssertEqual(successCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 0)
    }

    func testClearPersistsEmptyDraftWithoutCreatingAnItem() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let scheduler = ManualDraftWriteScheduler()
        let store = DraftStore(context: context, scheduler: scheduler)
        store.stage(text: "discard me", updatedAt: Date(timeIntervalSince1970: 30))
        let clearedAt = Date(timeIntervalSince1970: 31)

        try store.clear(updatedAt: clearedAt)

        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertEqual(try store.restore(), DraftSnapshot(text: "", updatedAt: clearedAt))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<IdeaItem>()).count, 0)
    }

    func testSuccessCallbackCanStageNextDraftWithoutCompletedClearRemovingIt() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let existing = DraftSnapshot(
            text: "submitted draft",
            updatedAt: Date(timeIntervalSince1970: 32)
        )
        context.insert(Draft(text: existing.text, updatedAt: existing.updatedAt))
        try context.save()
        let store = DraftStore(context: context, scheduler: ManualDraftWriteScheduler())
        let next = DraftSnapshot(
            text: "replacement draft",
            updatedAt: Date(timeIntervalSince1970: 33)
        )
        var successCount = 0
        store.onWriteSuccess = {
            successCount += 1
            if successCount == 1 {
                store.stage(text: next.text, updatedAt: next.updatedAt)
            }
        }

        try store.clear(updatedAt: Date(timeIntervalSince1970: 34))

        XCTAssertEqual(try store.restore(), next)

        try store.flush()

        XCTAssertEqual(try store.restore(), next)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.snapshot,
            next
        )
    }

    func testExistingDuplicateDraftRowsCollapseToNewestUpdatedAt() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        context.insert(Draft(text: "older", updatedAt: Date(timeIntervalSince1970: 40)))
        context.insert(Draft(text: "newer", updatedAt: Date(timeIntervalSince1970: 41)))
        try context.save()
        let store = DraftStore(context: context, scheduler: ManualDraftWriteScheduler())

        let restored = try store.restore()

        XCTAssertEqual(restored, DraftSnapshot(
            text: "newer",
            updatedAt: Date(timeIntervalSince1970: 41)
        ))
        let drafts = try context.fetch(FetchDescriptor<Draft>())
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.text, "newer")
    }

    func testFailedDuplicateRepairRollsBackAndRetryPersistsSingleton() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        context.insert(Draft(text: "older", updatedAt: Date(timeIntervalSince1970: 40)))
        context.insert(Draft(text: "newer", updatedAt: Date(timeIntervalSince1970: 41)))
        try context.save()
        var shouldFail = true
        let store = DraftStore(
            context: context,
            scheduler: ManualDraftWriteScheduler(),
            save: { context in
                if shouldFail {
                    shouldFail = false
                    throw TestError.writeFailed
                }
                try context.save()
            }
        )
        var reportedErrors: [TestError] = []
        store.onWriteFailure = { error in
            if let error = error as? TestError {
                reportedErrors.append(error)
            }
        }

        XCTAssertThrowsError(try store.restore()) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<Draft>()).map(\.text)),
            Set(["older", "newer"])
        )
        XCTAssertEqual(
            Set(try ModelContext(container).fetch(FetchDescriptor<Draft>()).map(\.text)),
            Set(["older", "newer"])
        )
        XCTAssertEqual(reportedErrors, [.writeFailed])

        XCTAssertEqual(
            try store.restore(),
            DraftSnapshot(text: "newer", updatedAt: Date(timeIntervalSince1970: 41))
        )
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).map(\.text),
            ["newer"]
        )
        XCTAssertEqual(reportedErrors, [.writeFailed])
    }

    func testFailedFlushKeepsPendingTextAndReportsWriteFailure() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        context.insert(Draft(text: "durable", updatedAt: Date(timeIntervalSince1970: 50)))
        try context.save()
        let scheduler = ManualDraftWriteScheduler()
        var shouldFail = true
        let store = DraftStore(
            context: context,
            scheduler: scheduler,
            save: { context in
                if shouldFail {
                    shouldFail = false
                    throw TestError.writeFailed
                }
                try context.save()
            }
        )
        var reportedErrors: [TestError] = []
        store.onWriteFailure = { error in
            if let error = error as? TestError {
                reportedErrors.append(error)
            }
        }
        let pendingDate = Date(timeIntervalSince1970: 51)
        store.stage(text: "still pending", updatedAt: pendingDate)

        scheduler.fire(0)

        XCTAssertEqual(reportedErrors, [.writeFailed])
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).first?.text, "durable")
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.text,
            "durable"
        )
        XCTAssertEqual(try store.restore(), DraftSnapshot(text: "still pending", updatedAt: pendingDate))

        try store.flush()

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.snapshot,
            DraftSnapshot(text: "still pending", updatedAt: pendingDate)
        )
        XCTAssertEqual(reportedErrors, [.writeFailed])
    }

    func testScheduledFetchFailureKeepsPendingTextAndReportsOnce() throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemory())
        let scheduler = ManualDraftWriteScheduler()
        let store = DraftStore(
            context: context,
            scheduler: scheduler,
            debounce: 0.250,
            fetchDrafts: { _, _ in throw TestError.fetchFailed },
            save: { try $0.save() }
        )
        var reportedErrors: [TestError] = []
        store.onWriteFailure = { error in
            if let error = error as? TestError {
                reportedErrors.append(error)
            }
        }
        let pendingSnapshot = DraftSnapshot(
            text: "still pending before save",
            updatedAt: Date(timeIntervalSince1970: 55)
        )
        store.stage(text: pendingSnapshot.text, updatedAt: pendingSnapshot.updatedAt)

        scheduler.fire(0)
        scheduler.fire(0)

        XCTAssertEqual(reportedErrors, [.fetchFailed])
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).count, 0)
        XCTAssertEqual(try store.restore(), pendingSnapshot)
    }

    func testFailedClearRollsBackSoLaterSaveCannotDiscardDraft() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let durableDate = Date(timeIntervalSince1970: 60)
        let durableSnapshot = DraftSnapshot(text: "must survive", updatedAt: durableDate)
        context.insert(Draft(text: durableSnapshot.text, updatedAt: durableSnapshot.updatedAt))
        try context.save()
        var shouldFail = true
        let store = DraftStore(
            context: context,
            scheduler: ManualDraftWriteScheduler(),
            save: { context in
                if shouldFail {
                    shouldFail = false
                    throw TestError.writeFailed
                }
                try context.save()
            }
        )
        var reportedErrors: [TestError] = []
        store.onWriteFailure = { error in
            if let error = error as? TestError {
                reportedErrors.append(error)
            }
        }

        XCTAssertThrowsError(try store.clear(updatedAt: Date(timeIntervalSince1970: 61))) { error in
            XCTAssertEqual(error as? TestError, .writeFailed)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Draft>()).first?.snapshot, durableSnapshot)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.snapshot,
            durableSnapshot
        )
        XCTAssertEqual(try store.restore(), durableSnapshot)
        XCTAssertEqual(reportedErrors, [.writeFailed])

        let unrelatedDate = Date(timeIntervalSince1970: 62)
        context.insert(IdeaItem(
            text: "unrelated",
            createdAt: unrelatedDate,
            updatedAt: unrelatedDate,
            movedAt: unrelatedDate
        ))
        try context.save()
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.snapshot,
            durableSnapshot
        )

        let retryDate = Date(timeIntervalSince1970: 63)
        try store.clear(updatedAt: retryDate)

        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<Draft>()).first?.snapshot,
            DraftSnapshot(text: "", updatedAt: retryDate)
        )
        XCTAssertEqual(reportedErrors, [.writeFailed])
    }
}

@MainActor
final class ManualDraftWriteScheduler: DraftWriteScheduling {
    private(set) var tokens: [ManualDraftWriteToken] = []

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DraftWriteCancellation {
        let token = ManualDraftWriteToken(delay: delay, action: action)
        tokens.append(token)
        return token
    }

    func fire(_ index: Int) {
        tokens[index].fire()
    }
}

@MainActor
final class ManualDraftWriteToken: DraftWriteCancellation {
    let delay: TimeInterval
    private(set) var isCancelled = false
    private var action: (@MainActor () -> Void)?

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.action = action
    }

    func cancel() {
        isCancelled = true
        action = nil
    }

    func fire() {
        guard !isCancelled, let action else { return }
        self.action = nil
        action()
    }
}

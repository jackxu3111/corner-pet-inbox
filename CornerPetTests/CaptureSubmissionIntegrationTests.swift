import Foundation
import SwiftData
import XCTest

@testable import CornerPet

@MainActor
final class CaptureSubmissionIntegrationTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 6_000)

    func testRealStoresPersistItemClearDraftAndKeepOpenWhenPointerInside() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let draftStore = makeDraftStore(context: context)
        let itemStore = ItemStore(context: context)
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInside: true,
            isPinned: false
        )
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("  persisted idea\n  ")

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        let inbox = try itemStore.fetchInbox()
        XCTAssertEqual(inbox.map(\.text), ["persisted idea"])
        XCTAssertEqual(createdItems, inbox)
        XCTAssertEqual(try draftStore.restore().text, "")
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    func testRealStoresCloseWhenPointerOutsideAndUnpinned() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let draftStore = makeDraftStore(context: context)
        let itemStore = ItemStore(context: context)
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInside: false,
            isPinned: false
        )
        viewModel.draftDidChange("close after save")

        _ = viewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(try itemStore.fetchInbox().map(\.text), ["close after save"])
        XCTAssertEqual(try draftStore.restore().text, "")
        XCTAssertEqual(viewModel.consumePanelCommand(), .close(.submittedOutside))
    }

    func testRealStoresKeepOpenWhenPinnedAndPointerOutside() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let draftStore = makeDraftStore(context: context)
        let itemStore = ItemStore(context: context)
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInside: false,
            isPinned: true
        )
        viewModel.draftDidChange("pinned idea")

        _ = viewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(try itemStore.fetchInbox().map(\.text), ["pinned idea"])
        XCTAssertEqual(try draftStore.restore().text, "")
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    func testLaterDebouncedWriteSuccessClearsPriorAutomaticSaveFailure() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let scheduler = ManualDraftWriteScheduler()
        var saveAttemptCount = 0
        let draftStore = DraftStore(
            context: context,
            scheduler: scheduler,
            debounce: 0.250,
            save: { context in
                saveAttemptCount += 1
                if saveAttemptCount == 1 {
                    throw CaptureSubmissionIntegrationTestError.saveFailed
                }
                try context.save()
            }
        )
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: ItemStore(context: context),
            pointerInside: true,
            isPinned: false
        )

        viewModel.draftDidChange("first pending draft")
        scheduler.fire(0)

        XCTAssertEqual(saveAttemptCount, 1)
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .flushDraft)

        viewModel.draftDidChange("second pending draft")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        scheduler.fire(1)

        XCTAssertEqual(saveAttemptCount, 2)
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.retryIntent)
        XCTAssertEqual(try draftStore.restore().text, "second pending draft")
    }

    func testRetryAfterClearFailureKeepsOneRealItemAndCompletesOnce() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        var draftSaveCallCount = 0
        let draftStore = makeDraftStore(context: context) { context in
            draftSaveCallCount += 1
            if draftSaveCallCount == 1 {
                throw CaptureSubmissionIntegrationTestError.saveFailed
            }
            try context.save()
        }
        let itemStore = ItemStore(context: context)
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInside: true,
            isPinned: false
        )
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("one durable idea")

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        let inboxAfterFailure = try itemStore.fetchInbox()
        XCTAssertEqual(inboxAfterFailure.map(\.text), ["one durable idea"])
        XCTAssertEqual(createdItems, [])
        XCTAssertEqual(viewModel.draftText, "one durable idea")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())

        viewModel.retryLastFailedOperation()

        let inboxAfterRetry = try itemStore.fetchInbox()
        XCTAssertEqual(inboxAfterRetry.count, 1)
        XCTAssertEqual(inboxAfterRetry, inboxAfterFailure)
        XCTAssertEqual(createdItems, inboxAfterRetry)
        XCTAssertEqual(draftSaveCallCount, 2)
        XCTAssertEqual(try draftStore.restore().text, "")
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testEditAfterClearFailurePersistsAsNewDraftWithoutDuplicatingRealItem() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        var draftSaveCallCount = 0
        let draftStore = makeDraftStore(context: context) { context in
            draftSaveCallCount += 1
            if draftSaveCallCount == 1 {
                throw CaptureSubmissionIntegrationTestError.saveFailed
            }
            try context.save()
        }
        let itemStore = ItemStore(context: context)
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInside: false,
            isPinned: false
        )
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("submitted idea")
        _ = viewModel.handleReturn(isShiftPressed: false)

        viewModel.draftDidChange("new draft after failure")
        viewModel.retryLastFailedOperation()

        let inbox = try itemStore.fetchInbox()
        XCTAssertEqual(inbox.map(\.text), ["submitted idea"])
        XCTAssertEqual(createdItems, inbox)
        XCTAssertEqual(draftSaveCallCount, 3)
        XCTAssertEqual(try draftStore.restore().text, "new draft after failure")
        XCTAssertEqual(viewModel.draftText, "new draft after failure")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testEscapeFlushSurvivesContainerRecreationWithoutFormalItem() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "CornerPetCaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "content.store")
        let draftText = "unfinished\nthought"

        do {
            let container = try ModelContainerFactory.make(at: storeURL)
            let context = ModelContext(container)
            let draftStore = makeDraftStore(context: context)
            let itemStore = ItemStore(context: context)
            let viewModel = makeViewModel(
                draftStore: draftStore,
                itemStore: itemStore,
                pointerInside: false,
                isPinned: false
            )
            viewModel.draftDidChange(draftText)

            viewModel.handleEscape()

            XCTAssertEqual(viewModel.consumePanelCommand(), .close(.escape))
            XCTAssertEqual(try itemStore.fetchInbox(), [])
        }

        let relaunchedContainer = try ModelContainerFactory.make(at: storeURL)
        let relaunchedContext = ModelContext(relaunchedContainer)
        let relaunchedDraftStore = makeDraftStore(context: relaunchedContext)
        let relaunchedItemStore = ItemStore(context: relaunchedContext)
        let relaunchedViewModel = makeViewModel(
            draftStore: relaunchedDraftStore,
            itemStore: relaunchedItemStore,
            pointerInside: true,
            isPinned: false
        )

        relaunchedViewModel.restoreDraft()

        XCTAssertEqual(relaunchedViewModel.draftText, draftText)
        XCTAssertEqual(try relaunchedItemStore.fetchInbox(), [])
    }

    private func makeDraftStore(
        context: ModelContext,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) -> DraftStore {
        DraftStore(
            context: context,
            scheduler: NonFiringDraftWriteScheduler(),
            debounce: 0.250,
            save: save
        )
    }

    private func makeViewModel(
        draftStore: DraftStore,
        itemStore: ItemStore,
        pointerInside: Bool,
        isPinned: Bool
    ) -> CaptureViewModel {
        CaptureViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            now: { [fixedDate] in fixedDate },
            pointerInsidePanel: { pointerInside },
            isPinned: { isPinned }
        )
    }
}

private enum CaptureSubmissionIntegrationTestError: Error {
    case saveFailed
}

@MainActor
private final class NonFiringDraftWriteScheduler: DraftWriteScheduling {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any DraftWriteCancellation {
        NonFiringDraftWriteToken()
    }
}

@MainActor
private final class NonFiringDraftWriteToken: DraftWriteCancellation {
    func cancel() {}
}

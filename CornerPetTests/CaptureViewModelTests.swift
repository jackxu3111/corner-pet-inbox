import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class CaptureViewModelTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_000)

    func testRestoreLoadsDraftAndPanelOpenRequestsFocusAtEnd() {
        let snapshot = DraftSnapshot(
            text: "restored\nthought",
            updatedAt: Date(timeIntervalSince1970: 900)
        )
        let draftStore = CaptureDraftStoreSpy(restoredSnapshot: snapshot)
        let viewModel = makeViewModel(draftStore: draftStore)

        viewModel.restoreDraft()

        XCTAssertEqual(viewModel.draftText, snapshot.text)
        XCTAssertNil(viewModel.consumePanelCommand())

        viewModel.panelDidOpen()

        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    func testDraftChangeStagesExactUntrimmedTextAndDate() {
        let draftStore = CaptureDraftStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore)
        let text = "  unfinished\nthought  "

        viewModel.draftDidChange(text)

        XCTAssertEqual(viewModel.draftText, text)
        XCTAssertEqual(
            draftStore.stagedSnapshots,
            [DraftSnapshot(text: text, updatedAt: fixedDate)]
        )
    }

    func testDraftActivityChangeReportsOnlyEmptyStateTransitions() {
        let viewModel = makeViewModel(draftStore: CaptureDraftStoreSpy())
        var activityChanges: [Bool] = []
        viewModel.onDraftActivityChanged = { activityChanges.append($0) }

        viewModel.draftDidChange("first")
        viewModel.draftDidChange("updated")
        viewModel.draftDidChange("")

        XCTAssertEqual(activityChanges, [true, false])
    }

    func testShiftReturnReturnsInsertNewlineWithoutSubmittingOrChangingText() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        let text = "line one"
        viewModel.draftDidChange(text)

        let action = viewModel.handleReturn(isShiftPressed: true)

        XCTAssertEqual(action, .insertNewline)
        XCTAssertEqual(viewModel.draftText, text)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testEscapeFlushesThenRequestsCloseWithoutClearingDraft() {
        let draftStore = CaptureDraftStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore)
        let text = "unfinished\nthought"
        viewModel.draftDidChange(text)

        viewModel.handleEscape()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 0)
        XCTAssertEqual(viewModel.draftText, text)
        XCTAssertEqual(viewModel.consumePanelCommand(), .close(.escape))
    }

    func testEscapeFlushFailureKeepsPanelOpenAndShowsPersistentError() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore)
        viewModel.draftDidChange("must survive")
        viewModel.panelDidOpen()

        viewModel.handleEscape()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(viewModel.draftText, "must survive")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())

        viewModel.draftDidChange("still visible")

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.draftText, "still visible")
    }

    func testSecondDirectEscapeAfterFailureClearsMatchingErrorAndClosesWithoutCreatingItem() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("escape directly again")

        viewModel.handleEscape()
        draftStore.flushError = nil
        viewModel.handleEscape()

        XCTAssertEqual(draftStore.flushedCount, 2)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, "escape directly again")
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.retryIntent)
        XCTAssertEqual(viewModel.consumePanelCommand(), .close(.escape))
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testConsumePanelCommandClearsTheOneShotCommand() {
        let viewModel = makeViewModel(draftStore: CaptureDraftStoreSpy())
        viewModel.panelDidOpen()

        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testDraftWriteCallbackShowsErrorWithoutClearingVisibleText() {
        let draftStore = CaptureDraftStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore)
        viewModel.draftDidChange("exact visible text")

        draftStore.reportWriteFailure()

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.draftText, "exact visible text")
    }

    func testRetryAfterDebouncedWriteFailureOnlyFlushesDraft() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("pending debounce")
        draftStore.reportWriteFailure()

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, "pending debounce")
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testRestoreFailurePreservesVisibleTextAndShowsPersistentError() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.restoreError = CaptureViewModelTestError.restoreFailed
        let viewModel = makeViewModel(draftStore: draftStore)
        viewModel.draftDidChange("visible before restore")

        viewModel.restoreDraft()

        XCTAssertEqual(viewModel.draftText, "visible before restore")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testRetryAfterRestoreFailureOnlyRestoresDraft() {
        let snapshot = DraftSnapshot(text: "recovered draft", updatedAt: fixedDate)
        let draftStore = CaptureDraftStoreSpy(restoredSnapshot: snapshot)
        let itemStore = CaptureItemStoreSpy()
        draftStore.restoreError = CaptureViewModelTestError.restoreFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.restoreDraft()
        draftStore.restoreError = nil

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(draftStore.restoreCallCount, 2)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, snapshot.text)
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testSecondDirectRestoreAfterFailureClearsMatchingErrorAndRestoresDraft() {
        let snapshot = DraftSnapshot(text: "restored directly", updatedAt: fixedDate)
        let draftStore = CaptureDraftStoreSpy(restoredSnapshot: snapshot)
        let itemStore = CaptureItemStoreSpy()
        draftStore.restoreError = CaptureViewModelTestError.restoreFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("visible before restore")

        viewModel.restoreDraft()
        draftStore.restoreError = nil
        viewModel.restoreDraft()

        XCTAssertEqual(draftStore.restoreCallCount, 2)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, snapshot.text)
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.retryIntent)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testFlushDraftPersistsWithoutClosingOrClearingVisibleText() {
        let draftStore = CaptureDraftStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore)
        viewModel.draftDidChange("flush only")

        viewModel.flushDraft()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 0)
        XCTAssertEqual(viewModel.draftText, "flush only")
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testRetryAfterExplicitFlushFailureOnlyFlushesDraft() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("flush retry")
        viewModel.flushDraft()
        draftStore.flushError = nil

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(draftStore.flushedCount, 2)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, "flush retry")
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testSecondDirectFlushAfterFailureClearsMatchingError() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("flush directly again")

        viewModel.flushDraft()
        draftStore.flushError = nil
        viewModel.flushDraft()

        XCTAssertEqual(draftStore.flushedCount, 2)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, "flush directly again")
        XCTAssertNil(viewModel.saveError)
        XCTAssertNil(viewModel.retryIntent)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testSuccessfulFlushDoesNotClearSubmitFailure() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        itemStore.createError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("submit still failed")
        _ = viewModel.handleReturn(isShiftPressed: false)

        viewModel.flushDraft()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .submitDraft)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testSuccessfulFlushDoesNotClearPendingSubmissionRecovery() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "pending clear")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("pending clear")
        _ = viewModel.handleReturn(isShiftPressed: false)

        viewModel.flushDraft()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(createdItems, [])
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .clearSubmittedDraft)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testAutomaticWriteSuccessDoesNotClearRestoreFailure() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.restoreError = CaptureViewModelTestError.restoreFailed
        let viewModel = makeViewModel(draftStore: draftStore)
        viewModel.restoreDraft()

        draftStore.reportWriteSuccess()

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .restoreDraft)
    }

    func testAutomaticWriteSuccessDoesNotClearEscapeFailure() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore)
        viewModel.draftDidChange("escape remains retryable")
        viewModel.handleEscape()

        draftStore.reportWriteSuccess()

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .escape)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testAutomaticWriteSuccessDoesNotClearSubmitFailure() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        itemStore.createError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("submit remains retryable")
        _ = viewModel.handleReturn(isShiftPressed: false)

        draftStore.reportWriteSuccess()

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .submitDraft)
    }

    func testAutomaticWriteSuccessDoesNotClearPendingClearFailure() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        itemStore.createdItem = makeItem(text: "pending clear")
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("pending clear")
        _ = viewModel.handleReturn(isShiftPressed: false)

        draftStore.reportWriteSuccess()

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .clearSubmittedDraft)
    }

    func testAutomaticWriteSuccessDoesNotClearPendingReplacementFailure() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        itemStore.createdItem = makeItem(text: "submitted text")
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("submitted text")
        _ = viewModel.handleReturn(isShiftPressed: false)
        viewModel.draftDidChange("replacement draft")
        draftStore.clearError = nil
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        viewModel.retryLastFailedOperation()

        draftStore.reportWriteSuccess()

        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertEqual(viewModel.retryIntent, .persistReplacementDraft)
    }

    func testRetryAfterEscapeFlushFailureClosesWithoutCreatingItem() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("escape retry")
        viewModel.handleEscape()
        draftStore.flushError = nil

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(draftStore.flushedCount, 2)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(viewModel.draftText, "escape retry")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .close(.escape))
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testSaveErrorProvidesStableEnglishAndChineseMessages() {
        XCTAssertEqual(CaptureSaveError.saveFailed.englishMessage, "Save failed. Try again.")
        XCTAssertEqual(CaptureSaveError.saveFailed.chineseMessage, "保存失败，请重试。")
    }

    func testEmptyNormalizedReturnCreatesNothingAndRefocuses() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        let whitespaceOnly = "  \n\t  "
        viewModel.draftDidChange(whitespaceOnly)

        let action = viewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(action, .submit)
        XCTAssertEqual(itemStore.createCallCount, 0)
        XCTAssertEqual(draftStore.clearedDates.count, 0)
        XCTAssertEqual(viewModel.draftText, whitespaceOnly)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    func testSuccessfulReturnClearsOnlyAfterItemStoreSuccess() {
        let operationLog = CaptureOperationLog()
        let draftStore = CaptureDraftStoreSpy(operationLog: operationLog)
        let itemStore = CaptureItemStoreSpy(operationLog: operationLog)
        itemStore.createdItem = makeItem(text: "idea")
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("  idea\n  ")

        let action = viewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(action, .submit)
        XCTAssertEqual(itemStore.receivedTexts, ["idea"])
        XCTAssertEqual(itemStore.receivedDates, [fixedDate])
        XCTAssertEqual(operationLog.entries, ["item.create", "draft.clear"])
        XCTAssertEqual(draftStore.clearedDates, [fixedDate])
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    func testItemSaveFailureKeepsExactDraftAndPanelOpen() {
        let operationLog = CaptureOperationLog()
        let draftStore = CaptureDraftStoreSpy(operationLog: operationLog)
        let itemStore = CaptureItemStoreSpy(operationLog: operationLog)
        itemStore.createError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        let text = "  keep me  "
        viewModel.draftDidChange(text)
        viewModel.panelDidOpen()

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        XCTAssertEqual(operationLog.entries, ["item.create"])
        XCTAssertEqual(draftStore.clearedDates.count, 0)
        XCTAssertEqual(viewModel.draftText, text)
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testRetryAfterFailureCreatesOnceThenClearsAndDismissesError() {
        let operationLog = CaptureOperationLog()
        let draftStore = CaptureDraftStoreSpy(operationLog: operationLog)
        let itemStore = CaptureItemStoreSpy(operationLog: operationLog)
        itemStore.createError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange(" retry me ")
        _ = viewModel.handleReturn(isShiftPressed: false)
        XCTAssertEqual(viewModel.saveError, .saveFailed)

        var errorObservedAtRetryCreate: CaptureSaveError?
        itemStore.onCreate = {
            errorObservedAtRetryCreate = viewModel.saveError
        }
        itemStore.createError = nil
        itemStore.createdItem = makeItem(text: "retry me")

        viewModel.retryLastFailedOperation()

        XCTAssertNil(errorObservedAtRetryCreate)
        XCTAssertEqual(itemStore.receivedTexts, ["retry me", "retry me"])
        XCTAssertEqual(
            operationLog.entries,
            ["item.create", "item.create", "draft.clear"]
        )
        XCTAssertEqual(draftStore.clearedDates, [fixedDate])
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    func testDismissErrorKeepsDraftAndAllowsLaterRetry() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        itemStore.createError = CaptureViewModelTestError.writeFailed
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("keep after dismissal")
        _ = viewModel.handleReturn(isShiftPressed: false)

        viewModel.dismissSaveError()

        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.draftText, "keep after dismissal")
        XCTAssertEqual(draftStore.clearedDates.count, 0)

        itemStore.createError = nil
        itemStore.createdItem = makeItem(text: "keep after dismissal")
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 2)
        XCTAssertEqual(draftStore.clearedDates, [fixedDate])
        XCTAssertEqual(viewModel.draftText, "")
    }

    func testRepeatedReturnWhileSubmittingIsIgnored() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        itemStore.createdItem = makeItem(text: "one item")
        var viewModel: CaptureViewModel!
        var nestedAction: CaptureKeyboardAction?
        var observedSubmitting = false
        itemStore.onCreate = {
            observedSubmitting = viewModel.isSubmitting
            nestedAction = viewModel.handleReturn(isShiftPressed: false)
        }
        viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("one item")

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        XCTAssertTrue(observedSubmitting)
        XCTAssertEqual(nestedAction, .submit)
        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 1)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testRetryAfterClearFailureOnlyClearsAndCompletesOriginalSubmissionOnce() {
        let operationLog = CaptureOperationLog()
        let draftStore = CaptureDraftStoreSpy(operationLog: operationLog)
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy(operationLog: operationLog)
        let item = makeItem(text: "partial persistence")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("partial persistence")

        _ = viewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 1)
        XCTAssertEqual(createdItems, [])
        XCTAssertEqual(viewModel.draftText, "partial persistence")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())

        draftStore.clearError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(
            operationLog.entries,
            ["item.create", "draft.clear", "draft.clear"]
        )
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testReturnWhileClearRecoveryIsPendingDoesNotCreateAnotherItem() {
        let operationLog = CaptureOperationLog()
        let draftStore = CaptureDraftStoreSpy(operationLog: operationLog)
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy(operationLog: operationLog)
        let item = makeItem(text: "pending submission")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("pending submission")

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)
        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(
            operationLog.entries,
            ["item.create", "draft.clear", "draft.clear"]
        )
        XCTAssertEqual(createdItems, [])
        XCTAssertEqual(viewModel.draftText, "pending submission")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())

        draftStore.clearError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 3)
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testReturnAfterDismissingClearFailureResumesClearWithoutCreating() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "dismissed clear")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("dismissed clear")
        _ = viewModel.handleReturn(isShiftPressed: false)
        viewModel.dismissSaveError()
        draftStore.clearError = nil

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testEditAfterClearFailureIsPreservedWhenSubmissionCompletes() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "submitted text")
        itemStore.createdItem = item
        let viewModel = makeViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInside: false
        )
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("submitted text")
        _ = viewModel.handleReturn(isShiftPressed: false)

        viewModel.draftDidChange("new draft after failure")
        draftStore.clearError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(draftStore.stagedSnapshots.last?.text, "new draft after failure")
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "new draft after failure")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testReplacementDraftFlushFailureRetriesOnlyThatFlush() {
        let operationLog = CaptureOperationLog()
        let draftStore = CaptureDraftStoreSpy(operationLog: operationLog)
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy(operationLog: operationLog)
        let item = makeItem(text: "submitted text")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("submitted text")
        _ = viewModel.handleReturn(isShiftPressed: false)
        viewModel.draftDidChange("replacement draft")
        draftStore.clearError = nil
        draftStore.flushError = CaptureViewModelTestError.writeFailed

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(createdItems, [])
        XCTAssertEqual(viewModel.draftText, "replacement draft")
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())

        draftStore.flushError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(draftStore.flushedCount, 2)
        XCTAssertEqual(operationLog.entries, ["item.create", "draft.clear", "draft.clear"])
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "replacement draft")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testReturnAfterDismissingReplacementFlushFailureRetriesOnlyFlush() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "submitted text")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("submitted text")
        _ = viewModel.handleReturn(isShiftPressed: false)
        viewModel.draftDidChange("replacement draft")
        draftStore.clearError = nil
        draftStore.flushError = CaptureViewModelTestError.writeFailed
        viewModel.retryLastFailedOperation()
        viewModel.dismissSaveError()
        draftStore.flushError = nil

        XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(draftStore.flushedCount, 2)
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "replacement draft")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testRepeatedClearFailuresNeverRecreateAndCompleteOnce() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "retry clear")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("retry clear")
        _ = viewModel.handleReturn(isShiftPressed: false)

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(createdItems, [])
        XCTAssertEqual(viewModel.saveError, .saveFailed)
        XCTAssertNil(viewModel.consumePanelCommand())

        draftStore.clearError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 3)
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())

        viewModel.retryLastFailedOperation()

        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 3)
        XCTAssertEqual(createdItems, [item])
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testFlushFailureCannotReplacePendingClearRecovery() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "pending clear")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("pending clear")
        _ = viewModel.handleReturn(isShiftPressed: false)
        draftStore.flushError = CaptureViewModelTestError.writeFailed

        viewModel.flushDraft()
        draftStore.clearError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testEscapeFailureCannotReplacePendingClearRecoveryOrClosePanel() {
        let draftStore = CaptureDraftStoreSpy()
        draftStore.clearError = CaptureViewModelTestError.writeFailed
        let itemStore = CaptureItemStoreSpy()
        let item = makeItem(text: "pending clear")
        itemStore.createdItem = item
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        var createdItems: [IdeaItemSnapshot] = []
        viewModel.onItemCreated = { createdItems.append($0) }
        viewModel.draftDidChange("pending clear")
        _ = viewModel.handleReturn(isShiftPressed: false)
        draftStore.flushError = CaptureViewModelTestError.writeFailed

        viewModel.handleEscape()
        draftStore.clearError = nil
        viewModel.retryLastFailedOperation()

        XCTAssertEqual(draftStore.flushedCount, 1)
        XCTAssertEqual(itemStore.createCallCount, 1)
        XCTAssertEqual(draftStore.clearedDates.count, 2)
        XCTAssertEqual(createdItems, [item])
        XCTAssertEqual(viewModel.draftText, "")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
        XCTAssertNil(viewModel.consumePanelCommand())
    }

    func testNilItemResultKeepsExactDraftAndRefocusesWithoutClearing() {
        let draftStore = CaptureDraftStoreSpy()
        let itemStore = CaptureItemStoreSpy()
        let viewModel = makeViewModel(draftStore: draftStore, itemStore: itemStore)
        viewModel.draftDidChange("nonempty")

        _ = viewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(itemStore.receivedTexts, ["nonempty"])
        XCTAssertEqual(draftStore.clearedDates.count, 0)
        XCTAssertEqual(viewModel.draftText, "nonempty")
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(viewModel.consumePanelCommand(), .focusInputAtEnd)
    }

    private func makeViewModel(
        draftStore: CaptureDraftStoreSpy,
        itemStore: CaptureItemStoreSpy = CaptureItemStoreSpy(),
        pointerInside: Bool = true,
        isPinned: Bool = false
    ) -> CaptureViewModel {
        CaptureViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            now: { [fixedDate] in fixedDate },
            pointerInsidePanel: { pointerInside },
            isPinned: { isPinned }
        )
    }

    private func makeItem(text: String) -> IdeaItemSnapshot {
        IdeaItemSnapshot(
            id: UUID(),
            text: text,
            bucket: .inbox,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            movedAt: fixedDate
        )
    }
}

private enum CaptureViewModelTestError: Error {
    case restoreFailed
    case writeFailed
}

@MainActor
private final class CaptureDraftStoreSpy: DraftStoring {
    var onWriteFailure: ((Error) -> Void)?
    var onWriteSuccess: (() -> Void)?
    var restoreError: Error?
    var flushError: Error?
    var clearError: Error?

    private(set) var stagedSnapshots: [DraftSnapshot] = []
    private(set) var restoreCallCount = 0
    private(set) var flushedCount = 0
    private(set) var clearedDates: [Date] = []

    private let restoredSnapshot: DraftSnapshot
    private let operationLog: CaptureOperationLog?

    init(
        restoredSnapshot: DraftSnapshot = DraftSnapshot(
            text: "",
            updatedAt: .distantPast
        ),
        operationLog: CaptureOperationLog? = nil
    ) {
        self.restoredSnapshot = restoredSnapshot
        self.operationLog = operationLog
    }

    func restore() throws -> DraftSnapshot {
        restoreCallCount += 1
        if let restoreError {
            throw restoreError
        }
        return restoredSnapshot
    }

    func stage(text: String, updatedAt: Date) {
        stagedSnapshots.append(DraftSnapshot(text: text, updatedAt: updatedAt))
    }

    func flush() throws {
        flushedCount += 1
        if let flushError {
            throw flushError
        }
    }

    func clear(updatedAt: Date) throws {
        clearedDates.append(updatedAt)
        operationLog?.append("draft.clear")
        if let clearError {
            throw clearError
        }
    }

    func reportWriteFailure() {
        onWriteFailure?(CaptureViewModelTestError.writeFailed)
    }

    func reportWriteSuccess() {
        onWriteSuccess?()
    }
}

@MainActor
private final class CaptureItemStoreSpy: ItemStoring {
    var createError: Error?
    var createdItem: IdeaItemSnapshot?
    var onCreate: (() -> Void)?

    private(set) var createCallCount = 0
    private(set) var receivedTexts: [String] = []
    private(set) var receivedDates: [Date] = []

    private let operationLog: CaptureOperationLog?

    init(operationLog: CaptureOperationLog? = nil) {
        self.operationLog = operationLog
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? {
        createCallCount += 1
        receivedTexts.append(text)
        receivedDates.append(date)
        operationLog?.append("item.create")
        onCreate?()
        if let createError {
            throw createError
        }
        return createdItem
    }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        []
    }
}

@MainActor
private final class CaptureOperationLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

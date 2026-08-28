import Foundation
import Observation

enum CaptureCloseReason: Equatable {
    case escape
    case submittedOutside
}

enum CapturePanelCommand: Equatable {
    case focusInputAtEnd
    case close(CaptureCloseReason)
}

enum CaptureSaveError: Equatable {
    case saveFailed

    var englishMessage: String {
        "Save failed. Try again."
    }

    var chineseMessage: String {
        "保存失败，请重试。"
    }
}

enum CaptureRetryIntent: Equatable {
    case restoreDraft
    case flushDraft
    case escape
    case submitDraft
    case clearSubmittedDraft
    case persistReplacementDraft
}

private struct PendingSubmission {
    let item: IdeaItemSnapshot
    let submittedDraftText: String
    let draftRevision: UInt
}

private enum PendingSubmissionState {
    case clearingDraft(PendingSubmission)
    case persistingReplacementDraft(PendingSubmission)

    var retryIntent: CaptureRetryIntent {
        switch self {
        case .clearingDraft:
            .clearSubmittedDraft
        case .persistingReplacementDraft:
            .persistReplacementDraft
        }
    }
}

@MainActor
@Observable
final class CaptureViewModel {
    private(set) var draftText = ""
    private(set) var saveError: CaptureSaveError?
    private(set) var isSubmitting = false
    private(set) var pendingPanelCommand: CapturePanelCommand?
    private(set) var retryIntent: CaptureRetryIntent?

    var onItemCreated: ((IdeaItemSnapshot) -> Void)?
    var onDraftActivityChanged: ((Bool) -> Void)?
    var onStateChanged: (() -> Void)?

    private let draftStore: any DraftStoring
    private let itemStore: any ItemStoring
    private let now: @MainActor () -> Date
    private let pointerInsidePanel: @MainActor () -> Bool
    private let isPinned: @MainActor () -> Bool
    private var activeDraftRetryIntent: CaptureRetryIntent?
    private var draftRevision: UInt = 0
    private var pendingSubmissionState: PendingSubmissionState?

    init(
        draftStore: any DraftStoring,
        itemStore: any ItemStoring,
        now: @escaping @MainActor () -> Date = { .now },
        pointerInsidePanel: @escaping @MainActor () -> Bool,
        isPinned: @escaping @MainActor () -> Bool
    ) {
        self.draftStore = draftStore
        self.itemStore = itemStore
        self.now = now
        self.pointerInsidePanel = pointerInsidePanel
        self.isPinned = isPinned

        draftStore.onWriteFailure = { [weak self] _ in
            guard let self else { return }
            recordFailure(
                retryIntent: activeDraftRetryIntent ?? .flushDraft
            )
        }
        draftStore.onWriteSuccess = { [weak self] in
            guard let self,
                  pendingSubmissionState == nil,
                  retryIntent == .flushDraft else {
                return
            }
            saveError = nil
            retryIntent = nil
            onStateChanged?()
        }
    }

    func restoreDraft() {
        do {
            let restoredText = try performDraftOperation(retryIntent: .restoreDraft) {
                try draftStore.restore().text
            }
            setDraftText(restoredText)
            clearFailure(matching: .restoreDraft)
        } catch {
            recordFailure(retryIntent: .restoreDraft)
        }
    }

    func panelDidOpen() {
        pendingPanelCommand = .focusInputAtEnd
    }

    func draftDidChange(_ text: String) {
        draftRevision &+= 1
        setDraftText(text)
        draftStore.stage(text: text, updatedAt: now())
    }

    func handleReturn(isShiftPressed: Bool) -> CaptureKeyboardAction {
        let action = CaptureKeyboardPolicy.action(
            keyCode: 36,
            isShiftPressed: isShiftPressed
        )
        if action == .submit {
            if pendingSubmissionState == nil {
                submitCurrentDraft()
            } else {
                retryLastFailedOperation()
            }
        }
        return action
    }

    func handleEscape() {
        pendingPanelCommand = nil
        do {
            try performDraftOperation(retryIntent: .escape) {
                try draftStore.flush()
            }
            clearFailure(matching: .escape)
            pendingPanelCommand = .close(.escape)
        } catch {
            recordFailure(retryIntent: .escape)
        }
    }

    func retryLastFailedOperation() {
        guard !isSubmitting, let retryIntent else { return }
        saveError = nil
        self.retryIntent = nil

        switch retryIntent {
        case .restoreDraft:
            restoreDraft()
        case .flushDraft:
            flushDraft()
        case .escape:
            handleEscape()
        case .submitDraft:
            submitCurrentDraft()
        case .clearSubmittedDraft:
            retryPendingSubmission()
        case .persistReplacementDraft:
            retryPendingSubmission()
        }
    }

    func dismissSaveError() {
        saveError = nil
        onStateChanged?()
    }

    func flushDraft() {
        do {
            try performDraftOperation(retryIntent: .flushDraft) {
                try draftStore.flush()
            }
            clearFailure(matching: .flushDraft)
        } catch {
            recordFailure(retryIntent: .flushDraft)
        }
    }

    func consumePanelCommand() -> CapturePanelCommand? {
        defer { pendingPanelCommand = nil }
        return pendingPanelCommand
    }

    private func submitCurrentDraft() {
        guard !isSubmitting, pendingSubmissionState == nil else { return }

        let normalized = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            pendingPanelCommand = .focusInputAtEnd
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            guard let item = try itemStore.createInboxItem(
                text: normalized,
                at: now()
            ) else {
                pendingPanelCommand = .focusInputAtEnd
                return
            }

            let submission = PendingSubmission(
                item: item,
                submittedDraftText: draftText,
                draftRevision: draftRevision
            )
            pendingSubmissionState = .clearingDraft(submission)
            clearDraftAndContinueSubmission(submission)
        } catch {
            recordFailure(retryIntent: .submitDraft)
            pendingPanelCommand = nil
        }
    }

    private func retryPendingSubmission() {
        guard let pendingSubmissionState else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        switch pendingSubmissionState {
        case let .clearingDraft(submission):
            clearDraftAndContinueSubmission(submission)
        case let .persistingReplacementDraft(submission):
            persistReplacementDraftAndFinishSubmission(submission)
        }
    }

    private func clearDraftAndContinueSubmission(_ submission: PendingSubmission) {
        do {
            try performDraftOperation(retryIntent: .clearSubmittedDraft) {
                try draftStore.clear(updatedAt: now())
            }
        } catch {
            recordFailure(retryIntent: .clearSubmittedDraft)
            pendingPanelCommand = nil
            return
        }

        let draftWasEdited = draftRevision != submission.draftRevision
            || draftText != submission.submittedDraftText
        guard draftWasEdited else {
            finishSubmission(submission, retainedDraftText: "")
            return
        }

        pendingSubmissionState = .persistingReplacementDraft(submission)
        persistReplacementDraftAndFinishSubmission(submission)
    }

    private func persistReplacementDraftAndFinishSubmission(
        _ submission: PendingSubmission
    ) {
        draftStore.stage(text: draftText, updatedAt: now())
        do {
            try performDraftOperation(retryIntent: .persistReplacementDraft) {
                try draftStore.flush()
            }
        } catch {
            recordFailure(retryIntent: .persistReplacementDraft)
            pendingPanelCommand = nil
            return
        }

        finishSubmission(submission, retainedDraftText: draftText)
    }

    private func finishSubmission(
        _ submission: PendingSubmission,
        retainedDraftText: String
    ) {
        pendingSubmissionState = nil
        setDraftText(retainedDraftText)
        saveError = nil
        retryIntent = nil
        onItemCreated?(submission.item)

        guard retainedDraftText.isEmpty else {
            pendingPanelCommand = .focusInputAtEnd
            return
        }

        pendingPanelCommand = switch PostSubmissionPolicy.decide(
            pointerInside: pointerInsidePanel(),
            isPinned: isPinned()
        ) {
        case .keepOpenAndRefocus:
            .focusInputAtEnd
        case .closePanel:
            .close(.submittedOutside)
        }
    }

    private func setDraftText(_ text: String) {
        let wasActive = !draftText.isEmpty
        draftText = text
        let isActive = !text.isEmpty
        if isActive != wasActive {
            onDraftActivityChanged?(isActive)
        }
        onStateChanged?()
    }

    private func performDraftOperation<T>(
        retryIntent: CaptureRetryIntent,
        operation: () throws -> T
    ) rethrows -> T {
        activeDraftRetryIntent = retryIntent
        defer { activeDraftRetryIntent = nil }
        return try operation()
    }

    private func recordFailure(retryIntent: CaptureRetryIntent) {
        saveError = .saveFailed
        self.retryIntent = pendingSubmissionState?.retryIntent ?? retryIntent
        onStateChanged?()
    }

    private func clearFailure(matching successfulIntent: CaptureRetryIntent) {
        guard retryIntent == successfulIntent else { return }
        saveError = nil
        retryIntent = nil
        onStateChanged?()
    }
}

import AppKit
import Foundation
import XCTest

@testable import CornerPet

@MainActor
final class ItemEditViewModelTests: XCTestCase {
    func testBeginKeepsOriginalUntilSaveOrCancel() {
        let item = makeItem(text: "original")
        let model = ItemEditViewModel(itemStore: EditStoreStub())

        XCTAssertTrue(model.beginEditing(item))
        model.setWorkingText("changed")

        XCTAssertEqual(model.originalText, "original")
        XCTAssertEqual(model.workingText, "changed")

        model.cancel()

        XCTAssertNil(model.activeItemID)
        XCTAssertEqual(model.workingText, "original")
    }

    func testReturnSavesExactWorkingTextAndUpdatesOnlyUpdatedAt() {
        let item = makeItem(text: "before", updatedAt: 10)
        let saved = IdeaItemSnapshot(
            id: item.id,
            text: " changed ",
            bucket: item.bucket,
            createdAt: item.createdAt,
            updatedAt: Date(timeIntervalSince1970: 20),
            movedAt: item.movedAt
        )
        let store = EditStoreStub(updateResults: [.success(saved)])
        let model = ItemEditViewModel(
            itemStore: store,
            dateProvider: { Date(timeIntervalSince1970: 20) }
        )
        XCTAssertTrue(model.beginEditing(item))
        model.setWorkingText(" changed ")

        let result = model.save()

        XCTAssertEqual(result, .saved(saved))
        XCTAssertNil(model.activeItemID)
        XCTAssertEqual(store.updateRequests, [
            .init(id: item.id, bucket: .inbox, text: " changed ", date: Date(timeIntervalSince1970: 20))
        ])
    }

    func testFocusLossSavesOnce() {
        let item = makeItem(text: "focus")
        let saved = item.updated(text: "saved", updatedAt: 2)
        let store = EditStoreStub(updateResults: [.success(saved)])
        let model = ItemEditViewModel(
            itemStore: store,
            dateProvider: { Date(timeIntervalSince1970: 2) }
        )
        XCTAssertTrue(model.beginEditing(item))
        model.setWorkingText("saved")

        XCTAssertEqual(model.save(), .saved(saved))
        XCTAssertEqual(model.save(), .missing)
        XCTAssertEqual(store.updateRequests.count, 1)
    }

    func testSaveFailureKeepsWorkingTextEditorAndError() {
        let item = makeItem(text: "before")
        let store = EditStoreStub(updateResults: [.failure(.saveFailed)])
        let model = ItemEditViewModel(itemStore: store)
        XCTAssertTrue(model.beginEditing(item))
        model.setWorkingText("unsaved")

        XCTAssertEqual(model.save(), .failed)
        XCTAssertEqual(model.activeItemID, item.id)
        XCTAssertEqual(model.workingText, "unsaved")
        XCTAssertEqual(model.error, .saveFailed)
    }

    func testDismissErrorClearsPersistentEditErrorWithoutDiscardingWorkingText() {
        let item = makeItem(text: "before")
        let store = EditStoreStub(updateResults: [.failure(.saveFailed)])
        let model = ItemEditViewModel(itemStore: store)
        XCTAssertTrue(model.beginEditing(item))
        model.setWorkingText("unsaved")

        XCTAssertEqual(model.save(), .failed)
        model.dismissError()

        XCTAssertNil(model.error)
        XCTAssertEqual(model.activeItemID, item.id)
        XCTAssertEqual(model.workingText, "unsaved")
    }

    func testFocusLossDelegateAttemptsSaveAndRetainsEditorOnFailure() {
        let item = makeItem(text: "before")
        let store = EditStoreStub(updateResults: [.failure(.saveFailed)])
        let model = ItemEditViewModel(itemStore: store)
        XCTAssertTrue(model.beginEditing(item))
        model.setWorkingText("unsaved")
        var focusLossCalls = 0
        let editor = InlineItemEditor(
            text: .constant("unsaved"),
            onCommit: {},
            onCancel: {},
            onFocusLoss: {
                focusLossCalls += 1
                _ = model.save()
            }
        )
        let coordinator = editor.makeCoordinator()
        let textView = InlineItemTextView(
            onCommit: {},
            onCancel: {},
            onFocusLoss: {}
        )
        textView.delegate = coordinator
        coordinator.textDidEndEditing(
            Notification(name: NSText.didEndEditingNotification, object: textView)
        )

        XCTAssertEqual(focusLossCalls, 1)
        XCTAssertEqual(model.activeItemID, item.id)
        XCTAssertEqual(model.error, .saveFailed)
        XCTAssertEqual(model.workingText, "unsaved")
    }

    func testRowOperationsAreDisabledForActiveEdit() {
        let first = makeItem(text: "first")
        let second = makeItem(text: "second")
        let model = ItemEditViewModel(itemStore: EditStoreStub())

        XCTAssertTrue(model.beginEditing(first))
        XCTAssertTrue(model.isEditing(first.id))
        XCTAssertFalse(model.isEditing(second.id))

        model.cancel()

        XCTAssertFalse(model.isEditing(first.id))
    }

    func testBeginningAnotherItemFirstSavesActiveEdit() {
        let first = makeItem(text: "first")
        let second = makeItem(text: "second")
        let saved = first.updated(text: "first saved", updatedAt: 3)
        let store = EditStoreStub(updateResults: [.success(saved)])
        let model = ItemEditViewModel(
            itemStore: store,
            dateProvider: { Date(timeIntervalSince1970: 3) }
        )
        XCTAssertTrue(model.beginEditing(first))
        model.setWorkingText("first saved")

        XCTAssertTrue(model.beginEditing(second))

        XCTAssertEqual(store.updateRequests.count, 1)
        XCTAssertEqual(model.activeItemID, second.id)
    }

    func testShiftReturnInsertsNewlineWithoutStoreCall() throws {
        var commitCount = 0
        let textView = InlineItemTextView(
            onCommit: { commitCount += 1 },
            onCancel: {},
            onFocusLoss: {}
        )
        textView.string = "before"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.keyDown(with: try makeKeyEvent(
            keyCode: 36,
            modifiers: .shift,
            characters: "\r"
        ))

        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(textView.string, "bef\nore")
    }

    func testMarkedTextReturnDoesNotCommit() throws {
        var commitCount = 0
        let textView = InlineItemTextView(
            onCommit: { commitCount += 1 },
            onCancel: {},
            onFocusLoss: {}
        )
        textView.string = "draft"
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.setMarkedText(
            "拼",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        textView.keyDown(with: try makeKeyEvent(keyCode: 36, characters: "\r"))

        XCTAssertEqual(commitCount, 0)
    }

    private func makeItem(
        id: UUID = UUID(),
        text: String,
        updatedAt: TimeInterval = 1
    ) -> IdeaItemSnapshot {
        let created = Date(timeIntervalSince1970: 0)
        let updated = Date(timeIntervalSince1970: updatedAt)
        return IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: .inbox,
            createdAt: created,
            updatedAt: updated,
            movedAt: created
        )
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

private extension IdeaItemSnapshot {
    func updated(text: String, updatedAt: TimeInterval) -> IdeaItemSnapshot {
        IdeaItemSnapshot(
            id: id,
            text: text,
            bucket: bucket,
            createdAt: createdAt,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            movedAt: movedAt
        )
    }
}

@MainActor
private final class EditStoreStub: ItemLifecycleStoring {
    struct UpdateRequest: Equatable {
        let id: UUID
        let bucket: ItemBucket
        let text: String
        let date: Date
    }

    private var updateResults: [Result<IdeaItemSnapshot?, EditStoreError>]
    private(set) var updateRequests: [UpdateRequest] = []

    init(updateResults: [Result<IdeaItemSnapshot?, EditStoreError>] = []) {
        self.updateResults = updateResults
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? { nil }
    func fetchInbox() throws -> [IdeaItemSnapshot] { [] }
    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot] { [] }
    func moveItem(
        id: UUID,
        from source: ItemBucket,
        to destination: ItemBucket,
        at date: Date
    ) throws -> IdeaItemSnapshot? { nil }
    func archiveInboxItem(id: UUID, at date: Date) throws -> IdeaItemSnapshot? { nil }

    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        updateRequests.append(.init(id: id, bucket: expectedBucket, text: text, date: date))
        guard !updateResults.isEmpty else { return nil }
        return try updateResults.removeFirst().get()
    }

    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool { false }
}

private enum EditStoreError: Error {
    case saveFailed
}

import Foundation
import Observation

enum ItemEditError: Equatable {
    case saveFailed
    case itemMissing
}

enum ItemEditSaveResult: Equatable {
    case saved(IdeaItemSnapshot)
    case failed
    case missing
}

@MainActor
@Observable
final class ItemEditViewModel {
    private(set) var activeItemID: UUID?
    private(set) var expectedBucket: ItemBucket?
    private(set) var originalText = ""
    private(set) var workingText = ""
    private(set) var error: ItemEditError?

    var onSnapshotSaved: ((IdeaItemSnapshot) -> Void)?
    var onStateChanged: (() -> Void)?

    private let itemStore: any ItemLifecycleStoring
    private let dateProvider: () -> Date

    init(
        itemStore: any ItemLifecycleStoring,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.itemStore = itemStore
        self.dateProvider = dateProvider
    }

    var isEditing: Bool {
        activeItemID != nil
    }

    @discardableResult
    func beginEditing(_ item: IdeaItemSnapshot) -> Bool {
        if activeItemID == item.id {
            return true
        }

        if activeItemID != nil {
            guard case .saved = save() else { return false }
        }

        activeItemID = item.id
        expectedBucket = item.bucket
        originalText = item.text
        workingText = item.text
        error = nil
        notifyStateChanged()
        return true
    }

    func setWorkingText(_ text: String) {
        guard activeItemID != nil else { return }
        workingText = text
        notifyStateChanged()
    }

    @discardableResult
    func save(at date: Date? = nil) -> ItemEditSaveResult {
        guard let activeItemID, let expectedBucket else {
            return .missing
        }

        do {
            guard let saved = try itemStore.updateItemText(
                id: activeItemID,
                expectedBucket: expectedBucket,
                text: workingText,
                at: date ?? dateProvider()
            ) else {
                error = .itemMissing
                notifyStateChanged()
                return .missing
            }

            self.activeItemID = nil
            self.expectedBucket = nil
            originalText = saved.text
            workingText = saved.text
            error = nil
            onSnapshotSaved?(saved)
            notifyStateChanged()
            return .saved(saved)
        } catch {
            self.error = .saveFailed
            notifyStateChanged()
            return .failed
        }
    }

    func cancel() {
        guard activeItemID != nil else { return }
        activeItemID = nil
        expectedBucket = nil
        workingText = originalText
        error = nil
        notifyStateChanged()
    }

    func dismissError() {
        guard error != nil else { return }
        error = nil
        notifyStateChanged()
    }

    func isEditing(_ id: UUID) -> Bool {
        activeItemID == id
    }

    private func notifyStateChanged() {
        onStateChanged?()
    }
}

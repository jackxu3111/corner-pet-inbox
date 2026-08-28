import Foundation
import Observation

enum ArchiveLoadError: Equatable {
    case loadFailed
}

@MainActor
@Observable
final class ArchiveViewModel {
    private(set) var allItems: [IdeaItemSnapshot] = []
    private(set) var items: [IdeaItemSnapshot] = []
    private(set) var loadError: ArchiveLoadError?
    private(set) var pendingDeletion: IdeaItemSnapshot?
    private(set) var deletionErrorItemID: UUID?

    var query = "" {
        didSet { applyFilter() }
    }

    private let archiveStore: any ArchiveItemStoring
    private let lifecycleStore: (any ItemLifecycleStoring)?
    let editViewModel: ItemEditViewModel?
    var onStateChanged: (() -> Void)?

    init(
        itemStore: any ArchiveItemStoring,
        lifecycleStore: (any ItemLifecycleStoring)? = nil,
        editViewModel: ItemEditViewModel? = nil
    ) {
        self.archiveStore = itemStore
        self.lifecycleStore = lifecycleStore ?? (itemStore as? any ItemLifecycleStoring)
        self.editViewModel = editViewModel
    }

    func load() {
        performLoad()
    }

    func retryLoad() {
        performLoad()
    }

    func search(_ query: String) {
        self.query = query
    }

    func replace(_ item: IdeaItemSnapshot) {
        defer { onStateChanged?() }
        guard item.bucket == .archive else {
            allItems.removeAll { $0.id == item.id }
            applyFilter()
            return
        }
        allItems.removeAll { $0.id == item.id }
        allItems.append(item)
        allItems.sort { lhs, rhs in
            if lhs.movedAt != rhs.movedAt { return lhs.movedAt > rhs.movedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        applyFilter()
    }

    func requestDelete(_ item: IdeaItemSnapshot) {
        defer { onStateChanged?() }
        guard editViewModel?.isEditing(item.id) != true else { return }
        pendingDeletion = item
        deletionErrorItemID = nil
    }

    func cancelDelete() {
        pendingDeletion = nil
        deletionErrorItemID = nil
        onStateChanged?()
    }

    func dismissDeleteConfirmation() {
        pendingDeletion = nil
        onStateChanged?()
    }

    @discardableResult
    func confirmDelete() -> Bool {
        defer { onStateChanged?() }
        guard let item = pendingDeletion else {
            return false
        }
        pendingDeletion = nil
        guard editViewModel?.isEditing(item.id) != true,
              let lifecycleStore else {
            deletionErrorItemID = item.id
            return false
        }

        do {
            guard try lifecycleStore.deletePermanently(id: item.id, expectedBucket: .archive) else {
                deletionErrorItemID = item.id
                return false
            }
            allItems.removeAll { $0.id == item.id }
            applyFilter()
            deletionErrorItemID = nil
            return true
        } catch {
            deletionErrorItemID = item.id
            return false
        }
    }

    private func performLoad() {
        defer { onStateChanged?() }
        do {
            allItems = try lifecycleStore?.fetchItems(in: .archive) ?? archiveStore.fetchArchive()
            applyFilter()
            loadError = nil
        } catch {
            allItems = []
            items = []
            loadError = .loadFailed
        }
    }

    private func applyFilter() {
        items = LibrarySearch.filter(allItems, query: query)
    }

}

import Foundation
import Observation

enum FavoritesLoadError: Equatable {
    case loadFailed
}

enum FavoritesActionError: Equatable {
    case moveFailed
}

@MainActor
@Observable
final class FavoritesViewModel {
    private(set) var allItems: [IdeaItemSnapshot] = []
    private(set) var items: [IdeaItemSnapshot] = []
    private(set) var loadError: FavoritesLoadError?
    private(set) var actionError: FavoritesActionError?
    private(set) var actionErrorItemID: UUID?
    private(set) var pendingDeletion: IdeaItemSnapshot?
    private(set) var deletionErrorItemID: UUID?
    let editViewModel: ItemEditViewModel?
    var onStateChanged: (() -> Void)?

    var query = "" {
        didSet { applyFilter() }
    }

    var onItemUnfavorited: ((IdeaItemSnapshot) -> Void)?

    private let itemStore: any ItemLifecycleStoring

    init(
        itemStore: any ItemLifecycleStoring,
        editViewModel: ItemEditViewModel? = nil
    ) {
        self.itemStore = itemStore
        self.editViewModel = editViewModel
    }

    func load() {
        defer { onStateChanged?() }
        do {
            allItems = try itemStore.fetchItems(in: .favorite)
            loadError = nil
            actionError = nil
            actionErrorItemID = nil
            applyFilter()
        } catch {
            allItems = []
            items = []
            loadError = .loadFailed
        }
    }

    func retryLoad() {
        load()
    }

    func search(_ query: String) {
        self.query = query
    }

    func upsert(_ item: IdeaItemSnapshot) {
        defer { onStateChanged?() }
        guard item.bucket == .favorite else { return }
        allItems.removeAll { $0.id == item.id }
        allItems.append(item)
        sortItems()
        applyFilter()
    }

    func unfavorite(_ item: IdeaItemSnapshot, at date: Date = Date()) {
        defer { onStateChanged?() }
        guard editViewModel?.isEditing(item.id) != true else { return }
        do {
            guard let restored = try itemStore.moveItem(
                id: item.id,
                from: .favorite,
                to: .inbox,
                at: date
            ), restored.bucket == .inbox else {
                markActionFailed(for: item.id)
                return
            }

            allItems.removeAll { $0.id == item.id }
            applyFilter()
            actionError = nil
            actionErrorItemID = nil
            onItemUnfavorited?(restored)
        } catch {
            markActionFailed(for: item.id)
        }
    }

    func replace(_ item: IdeaItemSnapshot) {
        defer { onStateChanged?() }
        guard item.bucket == .favorite else {
            allItems.removeAll { $0.id == item.id }
            applyFilter()
            return
        }
        upsert(item)
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
        guard editViewModel?.isEditing(item.id) != true else {
            deletionErrorItemID = item.id
            return false
        }

        do {
            guard try itemStore.deletePermanently(id: item.id, expectedBucket: .favorite) else {
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

    private func applyFilter() {
        items = LibrarySearch.filter(allItems, query: query)
    }

    private func sortItems() {
        allItems.sort { lhs, rhs in
            if lhs.movedAt != rhs.movedAt {
                return lhs.movedAt > rhs.movedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func markActionFailed(for id: UUID) {
        actionError = .moveFailed
        actionErrorItemID = id
    }

}

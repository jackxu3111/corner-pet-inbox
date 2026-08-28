import Foundation
import Observation

enum InboxLoadError: Equatable {
    case loadFailed
}

@MainActor
@Observable
final class InboxViewModel {
    private(set) var items: [IdeaItemSnapshot] = []
    private(set) var loadError: InboxLoadError?
    private(set) var completionErrorItemID: UUID?
    private(set) var favoriteErrorItemID: UUID?
    private(set) var pendingDeletion: IdeaItemSnapshot?
    private(set) var deletionErrorItemID: UUID?
    private(set) var archiveUndoOffer: ArchiveUndoOffer?
    private(set) var archiveUndoError: ArchiveUndoError?

    private let itemStore: any InboxItemStoring
    private let lifecycleStore: (any ItemLifecycleStoring)?
    let editViewModel: ItemEditViewModel?
    let archiveUndoController: ArchiveUndoController?

    var onItemFavorited: ((IdeaItemSnapshot) -> Void)?
    var onStateChanged: (() -> Void)?

    init(
        itemStore: any InboxItemStoring,
        archiveUndoController: ArchiveUndoController? = nil,
        lifecycleStore: (any ItemLifecycleStoring)? = nil,
        editViewModel: ItemEditViewModel? = nil
    ) {
        self.itemStore = itemStore
        self.lifecycleStore = lifecycleStore ?? (itemStore as? any ItemLifecycleStoring)
        self.editViewModel = editViewModel
        self.archiveUndoController = archiveUndoController
        syncArchiveUndoState()
        archiveUndoController?.onStateChanged = { [weak self, weak archiveUndoController] in
            guard let self, let archiveUndoController else { return }
            self.archiveUndoOffer = archiveUndoController.offer
            self.archiveUndoError = archiveUndoController.error
            self.onStateChanged?()
        }
        archiveUndoController?.onUndoSucceeded = { [weak self] item in
            self?.prepend(item)
        }
    }

    func load() {
        performLoad()
    }

    func retryLoad() {
        performLoad()
    }

    func prepend(_ item: IdeaItemSnapshot) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        onStateChanged?()
    }

    func complete(_ item: IdeaItemSnapshot, at date: Date = Date()) {
        defer { onStateChanged?() }
        guard editViewModel?.isEditing(item.id) != true else { return }
        do {
            guard let archived = try itemStore.archiveInboxItem(id: item.id, at: date) else {
                completionErrorItemID = item.id
                return
            }

            items.removeAll { $0.id == item.id }
            completionErrorItemID = nil
            archiveUndoController?.didArchive(archived)
            syncArchiveUndoState()
        } catch {
            completionErrorItemID = item.id
        }
    }

    func favorite(_ item: IdeaItemSnapshot, at date: Date = Date()) {
        defer { onStateChanged?() }
        guard editViewModel?.isEditing(item.id) != true else { return }
        guard let lifecycleStore else {
            favoriteErrorItemID = item.id
            return
        }

        do {
            guard let favorite = try lifecycleStore.moveItem(
                id: item.id,
                from: .inbox,
                to: .favorite,
                at: date
            ), favorite.bucket == .favorite else {
                favoriteErrorItemID = item.id
                return
            }

            items.removeAll { $0.id == item.id }
            favoriteErrorItemID = nil
            onItemFavorited?(favorite)
        } catch {
            favoriteErrorItemID = item.id
        }
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
            guard try lifecycleStore.deletePermanently(id: item.id, expectedBucket: .inbox) else {
                deletionErrorItemID = item.id
                return false
            }
            items.removeAll { $0.id == item.id }
            deletionErrorItemID = nil
            return true
        } catch {
            deletionErrorItemID = item.id
            return false
        }
    }

    func replace(_ item: IdeaItemSnapshot) {
        defer { onStateChanged?() }
        guard item.bucket == .inbox else {
            items.removeAll { $0.id == item.id }
            return
        }
        prepend(item)
    }

    func undoLastArchive() {
        defer { onStateChanged?() }
        archiveUndoController?.undo()
        syncArchiveUndoState()
    }

    private func syncArchiveUndoState() {
        archiveUndoOffer = archiveUndoController?.offer
        archiveUndoError = archiveUndoController?.error
    }

    private func performLoad() {
        defer { onStateChanged?() }
        do {
            items = try itemStore.fetchInbox()
            loadError = nil
        } catch {
            items = []
            loadError = .loadFailed
        }
    }
}

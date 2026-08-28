import AppKit
import SwiftData
import SwiftUI

@MainActor
protocol CaptureComposing: AnyObject {
    var captureViewModel: CaptureViewModel { get }
    var isAutoHideProtected: Bool { get }
    var onAutoHideProtectionChanged: ((Bool) -> Void)? { get set }
    var panelContentStatus: PanelContentStatus { get }

    func makeRootView() -> AnyView
    func applicationWillTerminate()
    func saveActiveEditForExternalFocus() -> ItemEditSaveResult?
    func configurePanelPinning(
        isPinned: @escaping @MainActor () -> Bool,
        onTogglePin: @escaping @MainActor () -> Void
    )
}

extension CaptureComposing {
    var panelContentStatus: PanelContentStatus {
        PanelContentStatus(hasDraft: false, hasItemEdit: false, hasError: false)
    }

    func saveActiveEditForExternalFocus() -> ItemEditSaveResult? {
        nil
    }

    func configurePanelPinning(
        isPinned: @escaping @MainActor () -> Bool,
        onTogglePin: @escaping @MainActor () -> Void
    ) {}
}

@MainActor
@Observable
final class PanelPinStateBox {
    var isPinned = false
}

@MainActor
final class CaptureCompositionRoot: CaptureComposing {
    let container: ModelContainer
    let draftStore: DraftStore
    let itemStore: ItemStore
    let editViewModel: ItemEditViewModel
    let captureViewModel: CaptureViewModel
    let inboxViewModel: InboxViewModel
    let favoritesViewModel: FavoritesViewModel
    let archiveViewModel: ArchiveViewModel
    let shellViewModel: CaptureShellViewModel

    var isAutoHideProtected: Bool {
        !captureViewModel.draftText.isEmpty || editViewModel.isEditing
    }
    var panelContentStatus: PanelContentStatus {
        PanelContentStatus(
            hasDraft: !captureViewModel.draftText.isEmpty,
            hasItemEdit: editViewModel.isEditing,
            hasError: captureViewModel.saveError != nil
                || editViewModel.error != nil
                || inboxViewModel.loadError != nil
                || inboxViewModel.completionErrorItemID != nil
                || inboxViewModel.favoriteErrorItemID != nil
                || inboxViewModel.deletionErrorItemID != nil
                || inboxViewModel.archiveUndoError != nil
                || archiveViewModel.loadError != nil
                || archiveViewModel.deletionErrorItemID != nil
                || favoritesViewModel.loadError != nil
                || favoritesViewModel.actionError != nil
                || favoritesViewModel.deletionErrorItemID != nil
        )
    }
    var onAutoHideProtectionChanged: ((Bool) -> Void)?

    private let pinStateBox: PanelPinStateBox
    private var pinStateProvider: @MainActor () -> Bool = { false }
    private var togglePinHandler: @MainActor () -> Void = {}

    func saveActiveEditForExternalFocus() -> ItemEditSaveResult? {
        guard editViewModel.isEditing else { return nil }
        return editViewModel.save()
    }

    private weak var panelController: CapturePanelController?

    init(
        container: ModelContainer,
        panelController: CapturePanelController,
        failPermanentDeletes: Bool = false,
        itemLifecycleStore: (any ItemLifecycleStoring)? = nil
    ) {
        self.container = container
        self.panelController = panelController

        let context = ModelContext(container)
        let draftStore = DraftStore(context: context)
        let itemStore = ItemStore(
            context: context,
            failPermanentDeletes: failPermanentDeletes
        )
        let editViewModel = ItemEditViewModel(
            itemStore: itemLifecycleStore ?? itemStore
        )
        let archiveUndoController = ArchiveUndoController(itemStore: itemStore)
        let favoritesViewModel = FavoritesViewModel(itemStore: itemStore, editViewModel: editViewModel)
        let inboxViewModel = InboxViewModel(
            itemStore: itemStore,
            archiveUndoController: archiveUndoController,
            lifecycleStore: itemStore,
            editViewModel: editViewModel
        )
        let archiveViewModel = ArchiveViewModel(
            itemStore: itemStore,
            lifecycleStore: itemStore,
            editViewModel: editViewModel
        )

        editViewModel.onSnapshotSaved = { [weak inboxViewModel, weak favoritesViewModel, weak archiveViewModel] item in
            inboxViewModel?.replace(item)
            favoritesViewModel?.replace(item)
            archiveViewModel?.replace(item)
        }

        inboxViewModel.onItemFavorited = { [weak favoritesViewModel] item in
            favoritesViewModel?.upsert(item)
        }
        favoritesViewModel.onItemUnfavorited = { [weak inboxViewModel] item in
            inboxViewModel?.prepend(item)
        }
        let pinStateBox = PanelPinStateBox()
        let captureViewModel = CaptureViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInsidePanel: { [weak panelController] in
                guard let frame = panelController?.keepOpenFrame else { return false }
                return frame.contains(NSEvent.mouseLocation)
            },
            isPinned: { pinStateBox.isPinned }
        )

        captureViewModel.onItemCreated = { [weak inboxViewModel] item in
            inboxViewModel?.prepend(item)
        }

        self.draftStore = draftStore
        self.itemStore = itemStore
        self.editViewModel = editViewModel
        self.captureViewModel = captureViewModel
        self.inboxViewModel = inboxViewModel
        self.favoritesViewModel = favoritesViewModel
        self.archiveViewModel = archiveViewModel
        let shellViewModel = CaptureShellViewModel()
        self.shellViewModel = shellViewModel
        self.pinStateBox = pinStateBox

        panelController.onFind = { [weak shellViewModel] in
            shellViewModel?.requestSearchFocus() ?? false
        }

        editViewModel.onStateChanged = { [weak self] in
            guard let self else { return }
            self.onAutoHideProtectionChanged?(self.isAutoHideProtected)
        }
        captureViewModel.onDraftActivityChanged = { [weak self] _ in
            guard let self else { return }
            self.onAutoHideProtectionChanged?(self.isAutoHideProtected)
        }
        captureViewModel.onStateChanged = { [weak self] in
            self?.onAutoHideProtectionChanged?(self?.isAutoHideProtected ?? false)
        }
        inboxViewModel.onStateChanged = { [weak self] in
            self?.onAutoHideProtectionChanged?(self?.isAutoHideProtected ?? false)
        }
        archiveViewModel.onStateChanged = { [weak self] in
            self?.onAutoHideProtectionChanged?(self?.isAutoHideProtected ?? false)
        }
        favoritesViewModel.onStateChanged = { [weak self] in
            self?.onAutoHideProtectionChanged?(self?.isAutoHideProtected ?? false)
        }
    }

    func makeRootView() -> AnyView {
        AnyView(CapturePanelView(
            captureViewModel: captureViewModel,
            inboxViewModel: inboxViewModel,
            favoritesViewModel: favoritesViewModel,
            archiveViewModel: archiveViewModel,
            shellViewModel: shellViewModel,
            pinStateBox: pinStateBox,
            pinState: pinStateProvider,
            pinAvailable: true,
            onTogglePin: togglePinHandler,
            onPanelCommand: { [weak panelController] command in
                panelController?.handleCaptureCommand(command)
            }
        ))
    }

    func configurePanelPinning(
        isPinned: @escaping @MainActor () -> Bool,
        onTogglePin: @escaping @MainActor () -> Void
    ) {
        pinStateProvider = isPinned
        pinStateBox.isPinned = isPinned()
        togglePinHandler = { [weak self] in
            onTogglePin()
            self?.pinStateBox.isPinned = isPinned()
        }
        panelController?.onTogglePin = togglePinHandler
    }

    func applicationWillTerminate() {
        captureViewModel.flushDraft()
    }
}

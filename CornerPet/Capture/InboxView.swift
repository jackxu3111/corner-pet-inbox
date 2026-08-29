import SwiftUI

struct InboxView: View {
    let viewModel: InboxViewModel

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 8) {
            if let offer = viewModel.archiveUndoOffer {
                ArchiveUndoBanner(
                    offer: offer,
                    error: viewModel.archiveUndoError,
                    onUndo: viewModel.undoLastArchive
                )
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    if viewModel.loadError != nil {
                        loadError
                    } else if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.items) { item in
                            ItemRow(
                                item: item,
                                hasCompletionError: viewModel.completionErrorItemID == item.id,
                                onComplete: { viewModel.complete(item) },
                                onFavorite: { viewModel.favorite(item) },
                                hasFavoriteError: viewModel.favoriteErrorItemID == item.id,
                                onDelete: { viewModel.requestDelete(item) },
                                hasDeleteError: viewModel.deletionErrorItemID == item.id,
                                editViewModel: viewModel.editViewModel
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.list")
        .confirmationDialog(
            L10n.localized(L10n.deleteConfirmation, locale: locale),
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.dismissDeleteConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                _ = viewModel.confirmDelete()
            } label: {
                Text(L10n.delete)
            }
            .accessibilityIdentifier("inbox.delete.confirm")
            Button(role: .cancel) {
                viewModel.cancelDelete()
            } label: {
                Text(L10n.cancel)
            }
            .accessibilityIdentifier("inbox.delete.cancel")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.inboxEmpty)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.empty")
    }

    private var loadError: some View {
        VStack(spacing: 9) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.orange)
            Text(L10n.inboxLoadFailed)
                .font(.callout)
            Button(action: viewModel.retryLoad) {
                Text(L10n.retry)
            }
            .accessibilityIdentifier("inbox.error.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.error")
    }
}

private struct ArchiveUndoBanner: View {
    let offer: ArchiveUndoOffer
    let error: ArchiveUndoError?
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: error == nil ? "archivebox" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == nil ? Color.secondary : Color.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.inboxArchived)
                Text(offer.item.text)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                if error != nil {
                    Text(L10n.restoreFailed)
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)

            Spacer(minLength: 4)

            Button(action: onUndo) {
                Text(L10n.undo)
            }
                .accessibilityIdentifier("inbox.archive.undo")
        }
        .padding(8)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.archive.undo.banner")
    }
}

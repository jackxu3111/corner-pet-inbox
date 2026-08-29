import SwiftUI

struct ArchiveView: View {
    let viewModel: ArchiveViewModel
    let focusRequest: Int

    @FocusState private var searchIsFocused: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 8) {
            searchField

            ScrollView {
                LazyVStack(spacing: 7) {
                    if viewModel.loadError != nil {
                        loadError
                    } else if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.items) { item in
                            ArchiveItemRow(
                                item: item,
                                editViewModel: viewModel.editViewModel,
                                onDelete: { viewModel.requestDelete(item) },
                                hasDeleteError: viewModel.deletionErrorItemID == item.id
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("archive.list")
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: viewModel.load)
        .onChange(of: focusRequest) { _, _ in
            LibrarySearchFocusRouting.requestFocus { searchIsFocused = $0 }
        }
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
            .accessibilityIdentifier("archive.delete.confirm")
            Button(role: .cancel) {
                viewModel.cancelDelete()
            } label: {
                Text(L10n.cancel)
            }
            .accessibilityIdentifier("archive.delete.cancel")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                L10n.localized(L10n.archiveSearch, locale: locale),
                text: Binding(
                    get: { viewModel.query },
                    set: viewModel.search
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchIsFocused)
            .accessibilityIdentifier("archive.search")
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.search("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.clearSearch))
                .help(Text(L10n.clearSearch))
                .accessibilityIdentifier("archive.search.clear")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(L10n.archiveEmpty)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("archive.empty")
    }

    private var loadError: some View {
        VStack(spacing: 9) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(L10n.archiveLoadFailed)
                .font(.callout)
            Button(action: viewModel.retryLoad) {
                Text(L10n.retry)
            }
                .accessibilityIdentifier("archive.error.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archive.error")
    }
}

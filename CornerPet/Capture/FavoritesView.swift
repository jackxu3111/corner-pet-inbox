import SwiftUI

struct FavoritesView: View {
    let viewModel: FavoritesViewModel

    @FocusState private var searchIsFocused: Bool

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
                            FavoriteItemRow(
                                item: item,
                                hasError: viewModel.actionErrorItemID == item.id,
                                onUnfavorite: { viewModel.unfavorite(item) },
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
            .accessibilityIdentifier("favorites.list")
        }
        .accessibilityElement(children: .contain)
        .onAppear(perform: viewModel.load)
        .confirmationDialog(
            "永久删除此想法？ / Delete this idea permanently?",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.dismissDeleteConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久删除 / Delete", role: .destructive) {
                _ = viewModel.confirmDelete()
            }
            .accessibilityIdentifier("favorites.delete.confirm")
            Button("取消 / Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            .accessibilityIdentifier("favorites.delete.cancel")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                "搜索收藏 / Search Favorites",
                text: Binding(
                    get: { viewModel.query },
                    set: viewModel.search
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchIsFocused)
            .accessibilityIdentifier("favorites.search")
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.search("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索 / Clear search")
                .accessibilityIdentifier("favorites.search.clear")
            }
        }
        .overlay {
            Button(action: {
                LibrarySearchFocusRouting.requestFocus { searchIsFocused = $0 }
            }) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty ? "还没有收藏 / No favorites yet" : "没有匹配项 / No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("favorites.empty")
    }

    private var loadError: some View {
        VStack(spacing: 9) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.orange)
            Text("收藏加载失败 / Couldn’t load Favorites")
                .font(.callout)
            Button("重试 / Retry", action: viewModel.retryLoad)
                .accessibilityIdentifier("favorites.error.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favorites.error")
    }
}

private struct FavoriteItemRow: View {
    let item: IdeaItemSnapshot
    let hasError: Bool
    let onUnfavorite: () -> Void
    let editViewModel: ItemEditViewModel?
    let onDelete: () -> Void
    let hasDeleteError: Bool

    @State private var focusRequest = 0

    init(
        item: IdeaItemSnapshot,
        hasError: Bool,
        onUnfavorite: @escaping () -> Void,
        editViewModel: ItemEditViewModel? = nil,
        onDelete: @escaping () -> Void = {},
        hasDeleteError: Bool = false
    ) {
        self.item = item
        self.hasError = hasError
        self.onUnfavorite = onUnfavorite
        self.editViewModel = editViewModel
        self.onDelete = onDelete
        self.hasDeleteError = hasDeleteError
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.yellow)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                if let editViewModel, editViewModel.isEditing(item.id) {
                    InlineItemEditor(
                        text: Binding(
                            get: { editViewModel.workingText },
                            set: editViewModel.setWorkingText
                        ),
                        focusRequest: focusRequest,
                        identifier: "favorites.item.editor.\(item.id.uuidString)",
                        onCommit: { _ = editViewModel.save() },
                        onCancel: editViewModel.cancel,
                        onFocusLoss: {
                            switch editViewModel.save() {
                            case .failed, .missing:
                                focusRequest &+= 1
                            case .saved:
                                break
                            }
                        }
                    )
                    .frame(minHeight: 28)
                    if editViewModel.error != nil {
                        ItemEditErrorMessage(
                            identifier: "favorites.item.editor.error.\(item.id.uuidString)",
                            dismissIdentifier: "favorites.item.editor.error.dismiss.\(item.id.uuidString)",
                            onDismiss: editViewModel.dismissError
                        )
                    }
                } else {
                    Text(item.text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2) {
                            guard editViewModel?.beginEditing(item) == true else { return }
                            focusRequest &+= 1
                        }
                }

                Text(item.movedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if hasDeleteError {
                    PermanentDeleteErrorMessage(
                        identifier: "favorites.item.delete.error.\(item.id.uuidString)"
                    )
                }
            }

            HStack(spacing: 7) {
                Button(action: onUnfavorite) {
                    Image(systemName: hasError ? "exclamationmark.circle" : "star.slash")
                        .foregroundStyle(hasError ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("取消收藏 / Remove favorite")
                .accessibilityLabel("取消收藏 / Remove favorite")
                .accessibilityIdentifier("favorites.item.unfavorite.\(item.id.uuidString)")

                Button(action: onDelete) {
                    Image(systemName: hasDeleteError ? "exclamationmark.circle" : "trash")
                        .foregroundStyle(hasDeleteError ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("永久删除 / Delete permanently")
                .accessibilityLabel("永久删除 / Delete permanently")
                .accessibilityIdentifier("favorites.item.delete.\(item.id.uuidString)")
            }
            .disabled(editViewModel?.isEditing(item.id) == true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favorites.item.\(item.id.uuidString)")
        .onChange(of: editViewModel?.activeItemID) { _, activeID in
            guard activeID == item.id else { return }
            focusRequest &+= 1
        }
    }
}

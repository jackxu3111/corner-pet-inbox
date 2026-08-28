import SwiftUI

struct ArchiveView: View {
    let viewModel: ArchiveViewModel

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
            .accessibilityIdentifier("archive.delete.confirm")
            Button("取消 / Cancel", role: .cancel) {
                viewModel.cancelDelete()
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
                "搜索归档 / Search Archive",
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
                .accessibilityLabel("清除搜索 / Clear search")
                .accessibilityIdentifier("archive.search.clear")
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
            Image(systemName: "archivebox")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("还没有归档 / No archived ideas yet")
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
            Text("归档加载失败 / Couldn’t load Archive")
                .font(.callout)
            Button("重试 / Retry", action: viewModel.retryLoad)
                .accessibilityIdentifier("archive.error.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archive.error")
    }
}

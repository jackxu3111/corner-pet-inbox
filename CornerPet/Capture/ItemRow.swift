import SwiftUI

struct ItemRow: View {
    let item: IdeaItemSnapshot
    let hasCompletionError: Bool
    let onComplete: () -> Void
    let onFavorite: () -> Void
    let hasFavoriteError: Bool
    let onDelete: () -> Void
    let hasDeleteError: Bool
    let editViewModel: ItemEditViewModel?

    @State private var focusRequest = 0

    init(
        item: IdeaItemSnapshot,
        hasCompletionError: Bool,
        onComplete: @escaping () -> Void,
        onFavorite: @escaping () -> Void = {},
        hasFavoriteError: Bool = false,
        onDelete: @escaping () -> Void = {},
        hasDeleteError: Bool = false,
        editViewModel: ItemEditViewModel? = nil
    ) {
        self.item = item
        self.hasCompletionError = hasCompletionError
        self.onComplete = onComplete
        self.onFavorite = onFavorite
        self.hasFavoriteError = hasFavoriteError
        self.onDelete = onDelete
        self.hasDeleteError = hasDeleteError
        self.editViewModel = editViewModel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onComplete) {
                Image(systemName: hasCompletionError ? "exclamationmark.circle" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(hasCompletionError ? .red : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(hasCompletionError ? "归档失败，点按重试 / Archive failed — click to retry" : "完成并归档 / Complete and archive")
            .accessibilityLabel(hasCompletionError ? "归档失败，重试 / Retry archive" : "完成并归档 / Complete and archive")
            .accessibilityIdentifier("inbox.item.complete.\(item.id.uuidString)")
            .disabled(editViewModel?.isEditing(item.id) == true)

            VStack(alignment: .leading, spacing: 5) {
                if let editViewModel, editViewModel.isEditing(item.id) {
                    InlineItemEditor(
                        text: Binding(
                            get: { editViewModel.workingText },
                            set: editViewModel.setWorkingText
                        ),
                        focusRequest: focusRequest,
                        identifier: "inbox.item.editor.\(item.id.uuidString)",
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
                            identifier: "inbox.item.editor.error.\(item.id.uuidString)",
                            dismissIdentifier: "inbox.item.editor.error.dismiss.\(item.id.uuidString)",
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

                Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if hasDeleteError {
                    PermanentDeleteErrorMessage(
                        identifier: "inbox.item.delete.error.\(item.id.uuidString)"
                    )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Button(action: onFavorite) {
                    Image(systemName: hasFavoriteError ? "exclamationmark.circle" : "star")
                        .foregroundStyle(hasFavoriteError ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("收藏 / Add to Favorites")
                .accessibilityLabel("收藏 / Add to Favorites")
                .accessibilityIdentifier("inbox.item.favorite.\(item.id.uuidString)")

                Button(action: onDelete) {
                    Image(systemName: hasDeleteError ? "exclamationmark.circle" : "trash")
                        .foregroundStyle(hasDeleteError ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("永久删除 / Delete permanently")
                .accessibilityLabel("永久删除 / Delete permanently")
                .accessibilityIdentifier("inbox.item.delete.\(item.id.uuidString)")
            }
            .disabled(editViewModel?.isEditing(item.id) == true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox.item.\(item.id.uuidString)")
        .onChange(of: editViewModel?.activeItemID) { _, activeID in
            guard activeID == item.id else { return }
            focusRequest &+= 1
        }
    }
}

import SwiftUI

struct ArchiveItemRow: View {
    let item: IdeaItemSnapshot
    let editViewModel: ItemEditViewModel?
    let onDelete: () -> Void
    let hasDeleteError: Bool

    @State private var focusRequest = 0

    init(
        item: IdeaItemSnapshot,
        editViewModel: ItemEditViewModel? = nil,
        onDelete: @escaping () -> Void = {},
        hasDeleteError: Bool = false
    ) {
        self.item = item
        self.editViewModel = editViewModel
        self.onDelete = onDelete
        self.hasDeleteError = hasDeleteError
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.green)
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
                        identifier: "archive.item.editor.\(item.id.uuidString)",
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
                            identifier: "archive.item.editor.error.\(item.id.uuidString)",
                            dismissIdentifier: "archive.item.editor.error.dismiss.\(item.id.uuidString)",
                            onDismiss: editViewModel.dismissError
                        )
                    }
                } else {
                    Text(item.text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(count: 2) {
                            beginEditing()
                        }
                        .accessibilityAction(named: Text(L10n.accessibilityEditAction)) {
                            beginEditing()
                        }
                }

                Text(item.movedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if hasDeleteError {
                    PermanentDeleteErrorMessage(
                        identifier: "archive.item.delete.error.\(item.id.uuidString)"
                    )
                }
            }

            Spacer(minLength: 0)

            Button(action: onDelete) {
                Image(systemName: hasDeleteError ? "exclamationmark.circle" : "trash")
                    .foregroundStyle(hasDeleteError ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(Text(L10n.deletePermanent))
            .accessibilityLabel(Text(L10n.deletePermanent))
            .accessibilityIdentifier("archive.item.delete.\(item.id.uuidString)")
            .disabled(editViewModel?.isEditing(item.id) == true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archive.item.\(item.id.uuidString)")
        .onChange(of: editViewModel?.activeItemID) { _, activeID in
            guard activeID == item.id else { return }
            focusRequest &+= 1
        }
    }

    private func beginEditing() {
        guard editViewModel?.beginEditing(item) == true else { return }
        focusRequest &+= 1
    }
}

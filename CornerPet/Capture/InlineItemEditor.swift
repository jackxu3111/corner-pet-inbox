import AppKit
import SwiftUI

struct ItemEditErrorMessage: View {
    let identifier: String
    let dismissIdentifier: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("保存失败 / Save failed")
                .foregroundStyle(.red)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 2)
            Button("关闭 / Dismiss", action: onDismiss)
                .buttonStyle(.link)
                .accessibilityIdentifier(dismissIdentifier)
        }
        .font(.caption2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifier).banner")
    }
}

struct PermanentDeleteErrorMessage: View {
    let identifier: String

    var body: some View {
        Text("删除失败 / Delete failed")
            .font(.caption2)
            .foregroundStyle(.red)
            .accessibilityLabel("删除失败 / Delete failed")
            .accessibilityIdentifier(identifier)
    }
}

struct InlineItemEditor: NSViewRepresentable {
    @Binding var text: String

    let focusRequest: Int
    let identifier: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onFocusLoss: () -> Void

    init(
        text: Binding<String>,
        focusRequest: Int = 0,
        identifier: String = "inline.item.editor",
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onFocusLoss: @escaping () -> Void
    ) {
        _text = text
        self.focusRequest = focusRequest
        self.identifier = identifier
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onFocusLoss = onFocusLoss
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = InlineItemTextView(
            onCommit: onCommit,
            onCancel: onCancel,
            onFocusLoss: onFocusLoss
        )
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 5, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityIdentifier(identifier)
        textView.setAccessibilityLabel("编辑想法 / Edit idea")

        scrollView.documentView = textView
        context.coordinator.update(parent: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
        guard let textView = scrollView.documentView as? InlineItemTextView else { return }

        textView.onCommit = onCommit
        textView.onCancel = onCancel
        textView.onFocusLoss = onFocusLoss
        if textView.string != text {
            textView.string = text
        }
        textView.applyFocusRequest(focusRequest)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: InlineItemEditor

        init(parent: InlineItemEditor) {
            self.parent = parent
        }

        func update(parent: InlineItemEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? InlineItemTextView else { return }
            let currentText = textView.string
            guard parent.text != currentText else { return }
            parent.text = currentText
        }

        func textDidEndEditing(_ notification: Notification) {
            guard notification.object is InlineItemTextView else { return }
            parent.onFocusLoss()
        }
    }
}

@MainActor
final class InlineItemTextView: NSTextView {
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onFocusLoss: () -> Void

    private let ownedTextStorage: NSTextStorage
    private var lastFocusRequest = 0

    init(
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onFocusLoss: @escaping () -> Void
    ) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onFocusLoss = onFocusLoss
        ownedTextStorage = textStorage
        super.init(frame: .zero, textContainer: textContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        switch CaptureKeyboardPolicy.action(
            keyCode: event.keyCode,
            isShiftPressed: event.modifierFlags.contains(.shift)
        ) {
        case .submit:
            onCommit()
        case .insertNewline:
            insertNewlineIgnoringFieldEditor(self)
        case .escape:
            onCancel()
        case .passThrough:
            super.keyDown(with: event)
        }
    }

    func applyFocusRequest(_ focusRequest: Int) {
        guard focusRequest != lastFocusRequest else { return }
        lastFocusRequest = focusRequest
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    func focusDidEndEditing() {
        onFocusLoss()
    }
}

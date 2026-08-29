import AppKit
import SwiftUI

struct CaptureTextLayoutMetrics {
    let contentHeight: CGFloat
    let visualLineCount: Int

    var requiresInternalScrolling: Bool {
        visualLineCount > CaptureLayout.inputVisibleLineLimit
            || contentHeight > CaptureLayout.inputMaximumHeight
    }
}

struct CaptureTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    @Environment(\.locale) private var locale

    let focusRequest: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void

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

        let textView = CaptureTextView(onSubmit: onSubmit, onEscape: onEscape)
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
        textView.textContainerInset = NSSize(width: 6, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityIdentifier("capture.input")
        updateAccessibility(on: textView)

        scrollView.documentView = textView
        context.coordinator.update(parent: self)
        context.coordinator.measure(textView, publishesText: false)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
        guard let textView = scrollView.documentView as? CaptureTextView else {
            return
        }

        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        updateAccessibility(on: textView)

        if textView.string != text {
            textView.string = text
        }

        let availableWidth = scrollView.contentSize.width
        if availableWidth > 0 {
            textView.textContainer?.containerSize = NSSize(
                width: availableWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        context.coordinator.measure(textView, publishesText: false)
        textView.applyFocusRequest(focusRequest)
    }

    private func updateAccessibility(on textView: CaptureTextView) {
        textView.setAccessibilityLabel(
            L10n.localized(L10n.captureInputLabel, locale: locale)
        )
        textView.setAccessibilityPlaceholderValue(
            L10n.localized(L10n.captureInputPlaceholder, locale: locale)
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: CaptureTextEditor

        init(parent: CaptureTextEditor) {
            self.parent = parent
        }

        func update(parent: CaptureTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CaptureTextView else {
                return
            }
            measure(textView, publishesText: true)
        }

        func measure(_ textView: CaptureTextView, publishesText: Bool) {
            let metrics = textView.layoutMetrics()
            let height = CaptureLayout.inputHeight(
                contentHeight: metrics.contentHeight,
                visualLineCount: metrics.visualLineCount
            )
            let currentText = textView.string
            textView.updateScroller(metrics: metrics)

            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                if publishesText, parent.text != currentText {
                    parent.text = currentText
                }
                if parent.measuredHeight != height {
                    parent.measuredHeight = height
                }
            }
        }
    }
}

@MainActor
final class CaptureTextView: NSTextView {
    var onSubmit: () -> Void
    var onEscape: () -> Void

    private let ownedTextStorage: NSTextStorage
    private var lastFocusRequest = 0

    init(
        onSubmit: @escaping () -> Void,
        onEscape: @escaping () -> Void
    ) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        self.onSubmit = onSubmit
        self.onEscape = onEscape
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
            onSubmit()
        case .insertNewline:
            insertNewlineIgnoringFieldEditor(self)
        case .escape:
            onEscape()
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

    func layoutMetrics() -> CaptureTextLayoutMetrics {
        guard let layoutManager, let textContainer else {
            return CaptureTextLayoutMetrics(contentHeight: 0, visualLineCount: 1)
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var visualLineCount = 0
        if glyphRange.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
                visualLineCount += 1
            }
        }

        let hasExtraLineFragment = layoutManager.extraLineFragmentTextContainer === textContainer
            && !layoutManager.extraLineFragmentRect.isEmpty
        if hasExtraLineFragment {
            visualLineCount += 1
        }

        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentBottom = hasExtraLineFragment
            ? max(usedRect.maxY, layoutManager.extraLineFragmentRect.maxY)
            : usedRect.maxY
        let contentHeight = ceil(contentBottom + (textContainerInset.height * 2))

        return CaptureTextLayoutMetrics(
            contentHeight: contentHeight,
            visualLineCount: max(1, visualLineCount)
        )
    }

    func updateScroller(metrics: CaptureTextLayoutMetrics) {
        enclosingScrollView?.hasVerticalScroller =
            metrics.requiresInternalScrolling
    }
}

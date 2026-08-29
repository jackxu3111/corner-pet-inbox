import AppKit
import XCTest

@testable import CornerPet

@MainActor
final class CaptureLayoutTests: XCTestCase {
    func testCaptureLayoutMatchesTheAcceptedPanel() {
        XCTAssertEqual(CaptureLayout.panelSize, CGSize(width: 360, height: 450))
        XCTAssertEqual(CaptureLayout.panelSize, PanelPositioner.defaultSize)
        XCTAssertEqual(CaptureLayout.headerHeight, 42)
        XCTAssertEqual(CaptureLayout.navigationHeight, 54)
        XCTAssertEqual(CaptureLayout.inputVisibleLineLimit, 5)
    }

    func testInputHeightClampsBetweenOneAndFiveLines() {
        XCTAssertEqual(CaptureLayout.inputHeight(contentHeight: 12), 30)
        XCTAssertEqual(CaptureLayout.inputHeight(contentHeight: 70), 70)
        XCTAssertEqual(CaptureLayout.inputHeight(contentHeight: 180), 110)
    }

    func testDestinationsHaveExactLocalizedCopy() {
        XCTAssertEqual(
            CaptureDestination.allCases.map {
                L10n.localized($0.title, locale: Locale(identifier: "zh-Hans"))
            },
            ["收件箱", "收藏", "归档", "设置"]
        )
        XCTAssertEqual(
            CaptureDestination.allCases.map {
                L10n.localized($0.title, locale: Locale(identifier: "en"))
            },
            ["Inbox", "Favorites", "Archive", "Settings"]
        )
    }

    func testShellStartsAtInboxAndStoresPlaceholderSelection() {
        let model = CaptureShellViewModel()

        XCTAssertEqual(model.selectedDestination, .inbox)

        model.select(.archive)

        XCTAssertEqual(model.selectedDestination, .archive)
    }

    func testShellRoutesSearchFocusOnlyForSearchDestinations() {
        let model = CaptureShellViewModel()

        XCTAssertFalse(model.requestSearchFocus())
        XCTAssertEqual(model.searchFocusRequest, 0)

        model.select(.archive)
        XCTAssertTrue(model.requestSearchFocus())
        XCTAssertEqual(model.searchFocusRequest, 1)

        model.select(.favorites)
        XCTAssertTrue(model.requestSearchFocus())
        XCTAssertEqual(model.searchFocusRequest, 2)

        model.select(.settings)
        XCTAssertFalse(model.requestSearchFocus())
        XCTAssertEqual(model.searchFocusRequest, 2)
    }

    func testCapturePanelViewConstructsWithInMemoryDependencies() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let draftStore = DraftStore(context: container.mainContext)
        let itemStore = ItemStore(context: container.mainContext)
        let captureViewModel = CaptureViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInsidePanel: { false },
            isPinned: { false }
        )

        _ = CapturePanelView(
            captureViewModel: captureViewModel,
            inboxViewModel: InboxViewModel(itemStore: itemStore),
            archiveViewModel: ArchiveViewModel(itemStore: itemStore),
            shellViewModel: CaptureShellViewModel(),
            pinState: { false },
            pinAvailable: false,
            onTogglePin: {},
            onPanelCommand: { _ in }
        )

        XCTAssertEqual(CaptureLayout.outerPadding, 12)
        XCTAssertEqual(CaptureDestination.favorites.systemImage, "star")
        XCTAssertEqual(CaptureDestination.archive.rawValue, "archive")
    }

    func testPlainReturnCallsSubmitWithoutInsertingNewline() throws {
        var submitCount = 0
        let textView = CaptureTextView(
            onSubmit: { submitCount += 1 },
            onEscape: {}
        )
        textView.string = "before"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.keyDown(with: try makeKeyEvent(keyCode: 36, characters: "\r"))

        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(textView.string, "before")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testShiftReturnUsesNativeNewlineInsertion() throws {
        var submitCount = 0
        let textView = CaptureTextView(
            onSubmit: { submitCount += 1 },
            onEscape: {}
        )
        textView.string = "before"
        textView.setSelectedRange(NSRange(location: 3, length: 2))

        textView.keyDown(with: try makeKeyEvent(
            keyCode: 36,
            modifiers: .shift,
            characters: "\r"
        ))

        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(textView.string, "bef\ne")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testEscapeCallsEscapeHandler() throws {
        var escapeCount = 0
        let textView = CaptureTextView(
            onSubmit: {},
            onEscape: { escapeCount += 1 }
        )

        textView.keyDown(with: try makeKeyEvent(
            keyCode: 53,
            characters: "\u{1b}"
        ))

        XCTAssertEqual(escapeCount, 1)
    }

    func testReturnDuringMarkedTextUsesNativeTextHandling() throws {
        var submitCount = 0
        let textView = CaptureTextView(
            onSubmit: { submitCount += 1 },
            onEscape: {}
        )
        textView.string = "draft"
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.setMarkedText(
            "拼",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())

        textView.keyDown(with: try makeKeyEvent(keyCode: 36, characters: "\r"))

        XCTAssertEqual(submitCount, 0)
    }

    func testFocusRequestMovesSelectionToUTF16End() {
        let textView = CaptureTextView(onSubmit: {}, onEscape: {})
        textView.string = "A🐱"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = textView

        textView.applyFocusRequest(1)

        XCTAssertTrue(window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testScrollerEnablesOnlyAboveFiveLineMaximum() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 110))
        let textView = CaptureTextView(onSubmit: {}, onEscape: {})
        scrollView.documentView = textView

        textView.updateScroller(metrics: CaptureTextLayoutMetrics(
            contentHeight: CaptureLayout.inputMaximumHeight,
            visualLineCount: CaptureLayout.inputVisibleLineLimit
        ))

        XCTAssertFalse(scrollView.hasVerticalScroller)

        textView.updateScroller(metrics: CaptureTextLayoutMetrics(
            contentHeight: CaptureLayout.inputMaximumHeight + 0.5,
            visualLineCount: CaptureLayout.inputVisibleLineLimit
        ))

        XCTAssertTrue(scrollView.hasVerticalScroller)
    }

    func testFiveActualLinesKeepGrowingWithoutInternalScrolling() {
        let (scrollView, textView) = makeLaidOutTextView(
            text: "one\ntwo\nthree\nfour\nfive"
        )
        let metrics = textView.layoutMetrics()

        XCTAssertEqual(metrics.visualLineCount, 5)
        XCTAssertLessThan(metrics.contentHeight, CaptureLayout.inputMaximumHeight)
        XCTAssertLessThan(
            CaptureLayout.inputHeight(
                contentHeight: metrics.contentHeight,
                visualLineCount: metrics.visualLineCount
            ),
            CaptureLayout.inputMaximumHeight
        )

        textView.updateScroller(metrics: metrics)

        XCTAssertFalse(scrollView.hasVerticalScroller)
    }

    func testSixthActualLineClampsToMaximumAndEnablesInternalScrolling() {
        let (scrollView, textView) = makeLaidOutTextView(
            text: "one\ntwo\nthree\nfour\nfive\nsix"
        )
        let metrics = textView.layoutMetrics()

        XCTAssertEqual(metrics.visualLineCount, 6)
        XCTAssertLessThan(metrics.contentHeight, CaptureLayout.inputMaximumHeight)
        XCTAssertEqual(
            CaptureLayout.inputHeight(
                contentHeight: metrics.contentHeight,
                visualLineCount: metrics.visualLineCount
            ),
            CaptureLayout.inputMaximumHeight
        )

        textView.updateScroller(metrics: metrics)

        XCTAssertTrue(scrollView.hasVerticalScroller)
    }

    private func makeLaidOutTextView(text: String) -> (NSScrollView, CaptureTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 110))
        let textView = CaptureTextView(onSubmit: {}, onEscape: {})
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 6, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: CaptureLayout.inputMaximumHeight
        )
        scrollView.documentView = textView
        textView.string = text
        return (scrollView, textView)
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}

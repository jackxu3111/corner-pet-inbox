import AppKit
import SwiftUI
import XCTest

@testable import CornerPet

@MainActor
final class CornerPanelDragRegionTests: XCTestCase {
    func testPinnedHeaderMouseDownHandsOffToWindowDrag() throws {
        guard NSScreen.screens.first != nil else {
            throw XCTSkip("A screen is required for AppKit drag tests")
        }

        let size = CGSize(width: 360, height: 450)
        let (panel, host) = try makeCapturePanel(size: size, isPinned: true)
        defer { panel.orderOut(nil) }

        let dragPoint = point(x: host.bounds.midX, fromTop: 2, in: size)
        XCTAssertTrue(host.hitTest(dragPoint) is CornerPanelDragRegionView)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: dragPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        panel.sendEvent(event)

        XCTAssertEqual(panel.performDragCallCount, 1)
    }

    func testUnpinnedHeaderDragRegionDoesNotHitOrHandOff() throws {
        guard NSScreen.screens.first != nil else {
            throw XCTSkip("A screen is required for AppKit drag tests")
        }

        let size = CGSize(width: 360, height: 450)
        let (panel, host) = try makeCapturePanel(size: size, isPinned: false)
        defer { panel.orderOut(nil) }

        let regionPoint = point(x: host.bounds.midX, fromTop: 2, in: size)
        XCTAssertFalse(host.hitTest(regionPoint) is CornerPanelDragRegionView)

        panel.sendEvent(try mouseEvent(type: .leftMouseDown, location: regionPoint, in: panel))

        XCTAssertEqual(panel.performDragCallCount, 0)
    }

    func testPinnedHeaderPinControlDoesNotHandOffToWindowDrag() throws {
        guard NSScreen.screens.first != nil else {
            throw XCTSkip("A screen is required for AppKit drag tests")
        }

        var toggleCount = 0
        let panel = makePanel(isPinned: true) {
            toggleCount += 1
        }
        defer { panel.orderOut(nil) }

        let host = try XCTUnwrap(panel.contentView as? NSHostingView<CaptureHeaderView>)
        let pinPoint = NSPoint(x: host.bounds.maxX - 15, y: host.bounds.midY)
        let hitView = host.hitTest(pinPoint)

        XCTAssertFalse(hitView is CornerPanelDragRegionView)

        panel.sendEvent(try mouseEvent(type: .leftMouseDown, location: pinPoint, in: panel))
        panel.sendEvent(try mouseEvent(type: .leftMouseUp, location: pinPoint, in: panel))

        XCTAssertEqual(panel.performDragCallCount, 0)
        XCTAssertEqual(toggleCount, 1)
    }

    func testPinnedPanelTopBandUsesFullWidthDragRegionAndLeavesControlsInteractive() throws {
        guard NSScreen.screens.first != nil else {
            throw XCTSkip("A screen is required for AppKit drag tests")
        }

        for size in [
            CGSize(width: 280, height: 320),
            CGSize(width: 360, height: 450),
            CGSize(width: 480, height: 640)
        ] {
            var toggleCount = 0
            let (panel, host) = try makeCapturePanel(
                size: size,
                isPinned: true,
                onTogglePin: { toggleCount += 1 }
            )
            defer { panel.orderOut(nil) }

            let topBandPoints = [
                point(x: 2, fromTop: 2, in: size),
                point(x: size.width / 2, fromTop: 2, in: size),
                point(x: size.width - 2, fromTop: 2, in: size),
                point(x: 26, fromTop: 32, in: size),
                point(x: 84, fromTop: 32, in: size),
                point(x: 1, fromTop: 58, in: size),
                point(x: size.width - 1, fromTop: 58, in: size),
                point(x: size.width / 2, fromTop: 58, in: size)
            ]

            for point in topBandPoints {
                XCTAssertTrue(
                    host.hitTest(point) is CornerPanelDragRegionView,
                    "Expected pinned top-band point \(point) to hit the drag region for \(size), got \(String(describing: host.hitTest(point)))"
                )
            }

            let pinPoint = point(x: size.width - 27, fromTop: 33, in: size)
            XCTAssertFalse(host.hitTest(pinPoint) is CornerPanelDragRegionView)

            panel.sendEvent(try mouseEvent(type: .leftMouseDown, location: pinPoint, in: panel))
            panel.sendEvent(try mouseEvent(type: .leftMouseUp, location: pinPoint, in: panel))

            XCTAssertEqual(panel.performDragCallCount, 0)
            XCTAssertEqual(toggleCount, 1)

            let inputPoint = point(x: size.width / 2, fromTop: 78, in: size)
            let contentPoint = point(x: size.width / 2, fromTop: 180, in: size)
            XCTAssertFalse(host.hitTest(inputPoint) is CornerPanelDragRegionView)
            XCTAssertFalse(host.hitTest(contentPoint) is CornerPanelDragRegionView)
        }
    }

    func testUnpinnedPanelTopBandNeverRoutesToDragRegion() throws {
        guard NSScreen.screens.first != nil else {
            throw XCTSkip("A screen is required for AppKit drag tests")
        }

        let size = CGSize(width: 360, height: 450)
        let (panel, host) = try makeCapturePanel(size: size, isPinned: false)
        defer { panel.orderOut(nil) }

        for point in [
            point(x: 2, fromTop: 2, in: size),
            point(x: size.width / 2, fromTop: 2, in: size),
            point(x: size.width - 2, fromTop: 2, in: size),
            point(x: 26, fromTop: 32, in: size),
            point(x: 84, fromTop: 32, in: size),
            point(x: size.width / 2, fromTop: 58, in: size)
        ] {
            XCTAssertFalse(host.hitTest(point) is CornerPanelDragRegionView)
        }
    }

    private func makePanel(
        isPinned: Bool,
        onTogglePin: @escaping () -> Void = {}
    ) -> DragSpyPanel {
        let panel = DragSpyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false

        let host = NSHostingView(rootView: CaptureHeaderView(
            isPinned: isPinned,
            pinAvailable: true,
            onTogglePin: onTogglePin
        ))
        panel.contentView = host
        panel.orderFront(nil)
        panel.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        return panel
    }

    private func makeCapturePanel(
        size: CGSize,
        isPinned: Bool,
        onTogglePin: @escaping () -> Void = {}
    ) throws -> (DragSpyPanel, NSHostingView<CapturePanelView>) {
        let container = try ModelContainerFactory.makeInMemory()
        let draftStore = DraftStore(context: container.mainContext)
        let itemStore = ItemStore(context: container.mainContext)
        let pinStateBox = PanelPinStateBox()
        pinStateBox.isPinned = isPinned
        let captureViewModel = CaptureViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInsidePanel: { false },
            isPinned: { pinStateBox.isPinned }
        )
        let host = NSHostingView(rootView: CapturePanelView(
            captureViewModel: captureViewModel,
            inboxViewModel: InboxViewModel(itemStore: itemStore),
            archiveViewModel: ArchiveViewModel(itemStore: itemStore),
            shellViewModel: CaptureShellViewModel(),
            pinStateBox: pinStateBox,
            pinState: { pinStateBox.isPinned },
            pinAvailable: true,
            onTogglePin: onTogglePin,
            onPanelCommand: { _ in }
        ))
        let panel = DragSpyPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.contentView = host
        panel.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        panel.orderFront(nil)
        panel.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        return (panel, host)
    }

    private func point(x: CGFloat, fromTop: CGFloat, in size: CGSize) -> NSPoint {
        NSPoint(x: x, y: size.height - fromTop)
    }

    private func descendant<T: NSView>(of root: NSView, as type: T.Type) -> T? {
        if let match = root as? T {
            return match
        }

        for child in root.subviews {
            if let match = descendant(of: child, as: type) {
                return match
            }
        }

        return nil
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        in panel: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
    }
}

@MainActor
private final class DragSpyPanel: NSPanel {
    private(set) var performDragCallCount = 0

    override func performDrag(with event: NSEvent) {
        performDragCallCount += 1
    }
}

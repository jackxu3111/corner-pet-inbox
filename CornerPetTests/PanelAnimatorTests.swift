import AppKit
import CoreGraphics
import XCTest

@testable import CornerPet

@MainActor
final class CornerPanelTests: XCTestCase {
    func testPanelIsFocusableFloatingNonactivatingAndFullScreenAuxiliary() {
        let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertEqual(panel.animationBehavior, .none)
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    func testPinnedPanelIsMovableResizableWithinExactBounds() {
        let panel = CornerPanel(contentRect: CGRect(
            x: 0,
            y: 0,
            width: 360,
            height: 450
        ))

        panel.setPinned(true)

        XCTAssertTrue(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.contentMinSize, PinnedPanelSizeStore.minimumSize)
        XCTAssertEqual(panel.contentMaxSize, PinnedPanelSizeStore.maximumSize)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))

        panel.setPinned(false)

        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertFalse(panel.styleMask.contains(.resizable))
    }

    func testControllerAppliesPinnedSizeAndPersistsResizeOnLiveResizeEnd() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for pinned panel tests")
        }
        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        var now: TimeInterval = 0
        let defaults = UserDefaults(suiteName: "CornerPet.PanelAnimatorTests.\(UUID().uuidString)")!
        let store = PinnedPanelSizeStore(defaults: defaults)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: store
        )

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(controller.isPinned)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.contentSize, PinnedPanelSizeStore.defaultSize)

        let frameBeforePin = panel.frame
        let contentSizeBeforePin = panel.contentSize

        controller.setPinned(false)
        XCTAssertEqual(panel.frame, frameBeforePin)
        XCTAssertEqual(panel.contentSize, contentSizeBeforePin)
        controller.setPinned(true)
        XCTAssertEqual(panel.frame, frameBeforePin)
        XCTAssertEqual(panel.contentSize, contentSizeBeforePin)

        panel.setContentSize(CGSize(width: 300, height: 350))
        controller.windowDidEndLiveResize()

        XCTAssertEqual(PinnedPanelSizeStore(defaults: defaults).load(), CGSize(width: 300, height: 350))
    }

    func testPresentUsesPersistedPinnedSizeDuringOpeningAndAfterCompletion() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for pinned panel tests")
        }
        let screenID = Self.displayID(for: screen)
        let defaults = UserDefaults(suiteName: "CornerPet.PanelAnimatorTests.\(UUID().uuidString)")!
        let store = PinnedPanelSizeStore(defaults: defaults)
        let savedSize = CGSize(width: 396, height: 496)
        store.save(savedSize)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { 0 },
            reducedMotionProvider: { true },
            pinnedSizeStore: store
        )
        defer { controller.panel?.orderOut(nil) }

        controller.present(screenID: screenID)
        let panel = try XCTUnwrap(controller.panel)
        let expectedFinalFrame = PanelPositioner.frame(
            inside: screen.visibleFrame,
            corner: .topLeft,
            size: savedSize
        )
        let expectedAnimator = PanelAnimator(
            finalFrame: expectedFinalFrame,
            corner: .topLeft,
            reducedMotion: true
        )
        _ = expectedAnimator.startOpening(at: 0)
        let expectedDuringOpening = expectedAnimator.sample(at: 0.060)

        _ = controller.tick(at: 0.060)
        XCTAssertEqual(panel.frame, expectedDuringOpening.frame.integral)

        _ = controller.tick(at: PanelAnimator.reducedMotionDuration)
        XCTAssertEqual(panel.contentSize, savedSize)
        XCTAssertEqual(panel.frame.size, savedSize)
    }

    func testPinTransitionsPreservePersistedFrameAndContentSizeExactly() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for pinned panel tests")
        }
        let screenID = Self.displayID(for: screen)
        let defaults = UserDefaults(suiteName: "CornerPet.PanelAnimatorTests.\(UUID().uuidString)")!
        let store = PinnedPanelSizeStore(defaults: defaults)
        let savedSize = CGSize(width: 396, height: 496)
        store.save(savedSize)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { 0 },
            reducedMotionProvider: { true },
            pinnedSizeStore: store
        )
        defer { controller.panel?.orderOut(nil) }

        controller.present(screenID: screenID)
        _ = controller.tick(at: PanelAnimator.reducedMotionDuration)
        let panel = try XCTUnwrap(controller.panel)
        let frameBeforePin = panel.frame
        let contentSizeBeforePin = panel.contentSize

        controller.setPinned(true)
        XCTAssertEqual(panel.frame, frameBeforePin)
        XCTAssertEqual(panel.contentSize, contentSizeBeforePin)

        controller.setPinned(false)
        XCTAssertEqual(panel.frame, frameBeforePin)
        XCTAssertEqual(panel.contentSize, contentSizeBeforePin)
    }

    func testFreshControllerPresentsWithSizeSavedByLiveResize() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for pinned panel tests")
        }
        let screenID = Self.displayID(for: screen)
        let defaults = UserDefaults(suiteName: "CornerPet.PanelAnimatorTests.\(UUID().uuidString)")!
        let store = PinnedPanelSizeStore(defaults: defaults)
        let savedSize = CGSize(width: 396, height: 496)
        var now: TimeInterval = 0
        let firstController = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: store
        )
        firstController.present(screenID: screenID)
        now = 0.120
        _ = firstController.tick(at: now)
        firstController.setPinned(true)
        firstController.panel?.setContentSize(savedSize)
        firstController.windowDidEndLiveResize()

        let freshController = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { 0 },
            reducedMotionProvider: { true },
            pinnedSizeStore: store
        )
        defer {
            firstController.panel?.orderOut(nil)
            freshController.panel?.orderOut(nil)
        }

        freshController.present(screenID: screenID)
        _ = freshController.tick(at: PanelAnimator.reducedMotionDuration)

        let freshPanel = try XCTUnwrap(freshController.panel)
        XCTAssertEqual(freshPanel.contentSize, savedSize)
        XCTAssertEqual(freshPanel.frame.size, savedSize)
    }

    func testControllerReturnsUnpinnedPanelToCornerWithRetainedSize() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for unpin tests")
        }
        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        var returnCount = 0
        controller.onReturnToCorner = { returnCount += 1 }

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        controller.panel?.setContentSize(CGSize(width: 300, height: 350))
        controller.panel?.setFrameOrigin(CGPoint(
            x: screen.visibleFrame.minX + 80,
            y: screen.visibleFrame.maxY - 350 - 80
        ))
        controller.setPinned(false)
        let retainedSize = try XCTUnwrap(controller.panel?.frame.size)

        controller.returnToCorner()
        XCTAssertNotEqual(controller.panel?.frame, PanelPositioner.frame(
            inside: screen.visibleFrame,
            corner: .topLeft,
            size: retainedSize
        ))

        now = 0.240
        _ = controller.tick(at: now)

        XCTAssertEqual(controller.panel?.frame, PanelPositioner.frame(
            inside: screen.visibleFrame,
            corner: .topLeft,
            size: retainedSize
        ))
        XCTAssertEqual(controller.panel?.frame.size, retainedSize)
        XCTAssertEqual(returnCount, 1)
    }

    func testControllerUnpinChoosesNearestCrossScreenCornerAndPersistsBeforeReturn() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for unpin target tests")
        }
        let originalScreenID = Self.displayID(for: screen)
        let defaults = UserDefaults(
            suiteName: "CornerPet.NearestCornerControllerTests.\(UUID().uuidString)"
        )!
        let cornerStore = TriggerCornerStore(defaults: defaults)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == originalScreenID ? screen : nil
            },
            screensProvider: {
                [
                    PanelScreenGeometry(
                        id: 1,
                        frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                        visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760)
                    ),
                    PanelScreenGeometry(
                        id: 2,
                        frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
                        visibleFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 760)
                    )
                ]
            },
            corner: .topLeft,
            clock: { now },
            reducedMotionProvider: { true }
        )
        var frameWhenPersisted: CGRect?
        var events: [CapturePanelLifecycleEvent] = []
        controller.onCornerChanged = { corner in
            cornerStore.save(corner)
            frameWhenPersisted = controller.panel?.frame
        }
        controller.onLifecycle = { events.append($0) }

        controller.present(screenID: originalScreenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        let movedFrame = CGRect(x: 1_500, y: 50, width: 300, height: 350)
        controller.panel?.setFrame(movedFrame, display: false)
        controller.setPinned(false)

        controller.returnToCorner()

        XCTAssertEqual(cornerStore.load(), .bottomRight)
        XCTAssertEqual(frameWhenPersisted, movedFrame)
        XCTAssertEqual(controller.panel?.frame, movedFrame)

        now = 0.240
        _ = controller.tick(at: now)
        XCTAssertEqual(
            controller.panel?.frame,
            CGRect(x: 1_700, y: 0, width: 300, height: 350)
        )

        controller.dismiss()
        XCTAssertEqual(events.last, .beganClosing(screenID: 2))
    }

    func testScreenDisconnectMovesOpenUnpinnedPanelToPrimaryFallback() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let originalScreenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == originalScreenID ? screen : nil
            },
            corner: .topRight,
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: PinnedPanelSizeStore(defaults: UserDefaults(
                suiteName: "CornerPet.ScreenDisconnectUnpinned.\(UUID().uuidString)"
            )!)
        )
        controller.present(screenID: originalScreenID)
        now = 0.120
        _ = controller.tick(at: now)
        let fallback = ScreenSnapshot(
            id: 999,
            frame: CGRect(x: 2_000, y: 100, width: 1_200, height: 800),
            visibleFrame: CGRect(x: 2_000, y: 100, width: 1_200, height: 760)
        )

        controller.handleScreenConfigurationChange(ScreenConfiguration(
            allScreens: [fallback],
            enabledScreens: [fallback],
            primaryDisplayID: fallback.id
        ))

        XCTAssertEqual(controller.currentScreenID, fallback.id)
        XCTAssertEqual(
            controller.panel?.frame,
            PanelPositioner.frame(
                inside: fallback.visibleFrame,
                corner: .topRight,
                size: PinnedPanelSizeStore.defaultSize
            )
        )
    }

    func testScreenDisconnectDuringOpeningRetargetsAnimationToPrimaryFallback() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let originalScreenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == originalScreenID ? screen : nil
            },
            corner: .topRight,
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: PinnedPanelSizeStore(defaults: UserDefaults(
                suiteName: "CornerPet.ScreenDisconnectOpening.\(UUID().uuidString)"
            )!)
        )
        defer { controller.panel?.orderOut(nil) }
        controller.present(screenID: originalScreenID)
        now = 0.040
        _ = controller.tick(at: now)
        let fallback = ScreenSnapshot(
            id: 999,
            frame: CGRect(x: 2_000, y: 100, width: 1_200, height: 800),
            visibleFrame: CGRect(x: 2_000, y: 100, width: 1_200, height: 760)
        )

        controller.handleScreenConfigurationChange(ScreenConfiguration(
            allScreens: [fallback],
            enabledScreens: [fallback],
            primaryDisplayID: fallback.id
        ))
        now = 0.160
        _ = controller.tick(at: now)

        XCTAssertEqual(controller.currentScreenID, fallback.id)
        XCTAssertEqual(
            controller.panel?.frame,
            PanelPositioner.frame(
                inside: fallback.visibleFrame,
                corner: .topRight,
                size: PinnedPanelSizeStore.defaultSize
            )
        )
    }

    func testScreenDisconnectDuringReturnRetargetsAnimationToPrimaryFallback() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let originalScreenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let originalGeometry = PanelScreenGeometry(
            id: originalScreenID,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == originalScreenID ? screen : nil
            },
            screensProvider: { [originalGeometry] },
            corner: .topLeft,
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: PinnedPanelSizeStore(defaults: UserDefaults(
                suiteName: "CornerPet.ScreenDisconnectReturning.\(UUID().uuidString)"
            )!)
        )
        defer { controller.panel?.orderOut(nil) }
        controller.present(screenID: originalScreenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        controller.panel?.setFrameOrigin(CGPoint(
            x: screen.visibleFrame.minX + 100,
            y: screen.visibleFrame.maxY - PinnedPanelSizeStore.defaultSize.height - 100
        ))
        controller.setPinned(false)
        controller.returnToCorner()
        now = 0.160
        _ = controller.tick(at: now)
        let fallback = ScreenSnapshot(
            id: 999,
            frame: CGRect(x: 2_000, y: 100, width: 1_200, height: 800),
            visibleFrame: CGRect(x: 2_000, y: 100, width: 1_200, height: 760)
        )

        controller.handleScreenConfigurationChange(ScreenConfiguration(
            allScreens: [fallback],
            enabledScreens: [fallback],
            primaryDisplayID: fallback.id
        ))
        now = 0.280
        _ = controller.tick(at: now)

        XCTAssertEqual(controller.currentScreenID, fallback.id)
        XCTAssertEqual(
            controller.panel?.frame,
            PanelPositioner.frame(
                inside: fallback.visibleFrame,
                corner: .topLeft,
                size: PinnedPanelSizeStore.defaultSize
            )
        )
    }

    func testScreenDisconnectKeepsPinnedPanelSizeAndClampsItIntoPrimaryFallback() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let originalScreenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == originalScreenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.present(screenID: originalScreenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        let movedFrame = CGRect(x: -5_000, y: -4_000, width: 420, height: 520)
        controller.panel?.setFrame(movedFrame, display: false)
        let fallback = ScreenSnapshot(
            id: 999,
            frame: CGRect(x: 2_000, y: 100, width: 1_200, height: 800),
            visibleFrame: CGRect(x: 2_000, y: 100, width: 1_200, height: 760)
        )

        controller.handleScreenConfigurationChange(ScreenConfiguration(
            allScreens: [fallback],
            enabledScreens: [fallback],
            primaryDisplayID: fallback.id
        ))

        XCTAssertEqual(controller.currentScreenID, fallback.id)
        XCTAssertEqual(controller.panel?.frame.size, movedFrame.size)
        XCTAssertTrue(fallback.visibleFrame.contains(controller.panel?.frame ?? .zero))
    }

    func testBringForwardPreservesPinnedPanelFrameAndState() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in requestedID == screenID ? screen : nil },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        let pinnedFrame = CGRect(x: 140, y: 180, width: 410, height: 510)
        controller.panel?.setFrame(pinnedFrame, display: false)

        controller.bringForward()

        XCTAssertTrue(controller.isPinned)
        XCTAssertEqual(controller.panel?.frame, pinnedFrame)
        XCTAssertTrue(controller.panel?.isVisible == true)
    }

    func testControllerCancelsCloseWhenReentryReversesDuringReturn() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for unpin reversal tests")
        }
        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.setPinned(true)
        controller.panel?.setFrameOrigin(CGPoint(x: 80, y: 120))
        controller.setPinned(false)
        controller.returnToCorner()

        controller.dismiss()
        controller.reverseClosing(screenID: screenID)

        now = 0.240
        _ = controller.tick(at: now)
        now = 0.360
        _ = controller.tick(at: now)

        XCTAssertTrue(controller.isVisible)
    }

    func testCommandShiftPFromCaptureTextViewFirstResponderUsesWindowEventPath() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for shortcut tests")
        }
        let screenID = Self.displayID(for: screen)
        let controller = makeController(screen: screen, screenID: screenID)
        let captureTextView = CaptureTextView(onSubmit: {}, onEscape: {})
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        host.addSubview(captureTextView)
        captureTextView.frame = host.bounds
        controller.installHostedContentFactory { host }

        var toggleCount = 0
        controller.onTogglePin = {
            toggleCount += 1
            controller.setPinned(!controller.isPinned)
        }
        controller.present(screenID: screenID)
        _ = controller.tick(at: 0.120)
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.makeFirstResponder(captureTextView))
        XCTAssertTrue(panel.firstResponder === captureTextView)

        panel.sendEvent(try shortcutEvent(for: panel))

        XCTAssertEqual(toggleCount, 1)
        XCTAssertTrue(controller.isPinned)
        XCTAssertTrue(panel.isPinned)
    }

    func testCommandShiftPFromInlineItemTextViewFirstResponderUsesWindowEventPath() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for shortcut tests")
        }
        let screenID = Self.displayID(for: screen)
        let controller = makeController(screen: screen, screenID: screenID)
        let inlineTextView = InlineItemTextView(onCommit: {}, onCancel: {}, onFocusLoss: {})
        inlineTextView.string = "editing through the inline editor"
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.documentView = inlineTextView
        controller.installHostedContentFactory { scrollView }

        var toggleCount = 0
        controller.onTogglePin = {
            toggleCount += 1
            controller.setPinned(!controller.isPinned)
        }
        controller.present(screenID: screenID)
        _ = controller.tick(at: 0.120)
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.makeFirstResponder(inlineTextView))
        XCTAssertTrue(panel.firstResponder === inlineTextView)

        panel.sendEvent(try shortcutEvent(for: panel))

        XCTAssertEqual(toggleCount, 1)
        XCTAssertTrue(controller.isPinned)
        XCTAssertTrue(panel.isPinned)
    }

    private func makeController(screen: NSScreen, screenID: UInt32) -> CapturePanelController {
        CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { 0 },
            reducedMotionProvider: { true }
        )
    }

    private func shortcutEvent(for panel: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0.120,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "p",
            charactersIgnoringModifiers: "p",
            isARepeat: false,
            keyCode: 35
        ))
    }

    private static func displayID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

@MainActor
final class PanelAnimatorTests: XCTestCase {
    func testReturningStartsAtRetainedFrameAfterCompletedOpening() {
        let targetFrame = CGRect(x: 108, y: 208, width: 320, height: 400)
        let retainedFrame = CGRect(x: 640, y: 120, width: 360, height: 450)
        let animator = PanelAnimator(
            finalFrame: targetFrame,
            corner: .topLeft,
            reducedMotion: true
        )

        _ = animator.startOpening(at: 0)
        _ = animator.sample(at: PanelAnimator.reducedMotionDuration)

        let initial = animator.startReturning(
            from: retainedFrame,
            to: targetFrame,
            at: 1
        )

        XCTAssertEqual(initial.progress, 0, accuracy: 0.0000001)
        XCTAssertEqual(initial.frame, retainedFrame)
        XCTAssertFalse(initial.isComplete)
    }

    func testStandardOpeningStartsAsACapsuleAnchoredToEachCorner() {
        let finalFrame = CGRect(x: 108, y: 208, width: 320, height: 400)
        let expectedCapsules: [(corner: TriggerCorner, frame: CGRect)] = [
            (.topLeft, CGRect(x: 108, y: 580, width: 44, height: 28)),
            (.topRight, CGRect(x: 384, y: 580, width: 44, height: 28)),
            (.bottomLeft, CGRect(x: 108, y: 208, width: 44, height: 28)),
            (.bottomRight, CGRect(x: 384, y: 208, width: 44, height: 28))
        ]

        for expectation in expectedCapsules {
            let animator = PanelAnimator(
                finalFrame: finalFrame,
                corner: expectation.corner,
                reducedMotion: false
            )

            XCTAssertEqual(animator.startOpening(at: 10).progress, 0)
            XCTAssertEqual(animator.sample(at: 10).frame, expectation.frame)
        }
    }

    func testStandardOpeningUsesNormalizedGrowthAndDelaysContentFade() {
        let finalFrame = CGRect(x: 108, y: 208, width: 320, height: 400)
        let animator = PanelAnimator(
            finalFrame: finalFrame,
            corner: .topLeft,
            reducedMotion: false
        )

        _ = animator.startOpening(at: 0)
        let half = animator.sample(at: 0.130)

        XCTAssertEqual(half.progress, 0.5, accuracy: 0.0000001)
        XCTAssertEqual(half.shellScale, 0.9997406360, accuracy: 0.0000001)
        XCTAssertEqual(half.contentAlpha, 0.589568, accuracy: 0.000001)
        XCTAssertEqual(half.windowAlpha, 1, accuracy: 0.0000001)

        var maximumShellScale: CGFloat = 0
        for index in 0...1_000 {
            let time = Double(index) * 0.000260
            maximumShellScale = max(maximumShellScale, animator.sample(at: time).shellScale)
        }
        XCTAssertLessThanOrEqual(maximumShellScale, 1.03)

        let end = animator.sample(at: 0.260)
        XCTAssertEqual(end.progress, 1, accuracy: 0.0000001)
        XCTAssertEqual(end.shellScale, 1, accuracy: 0.0000001)
        XCTAssertEqual(end.frame, finalFrame)
        XCTAssertEqual(end.contentAlpha, 1, accuracy: 0.0000001)
    }

    func testStandardClosingReachesHalfProgressAfterNinetyMilliseconds() {
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .bottomRight,
            reducedMotion: false
        )

        _ = animator.startOpening(at: 0)
        _ = animator.sample(at: 0.260)
        _ = animator.startClosing(at: 0.260)

        let half = animator.sample(at: 0.350)

        XCTAssertEqual(half.progress, 0.5, accuracy: 0.0000001)
        XCTAssertFalse(half.isComplete)
    }

    func testReversingAtHalfProgressPreservesTheSampleAndUsesOpeningDuration() {
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .bottomRight,
            reducedMotion: false
        )

        _ = animator.startOpening(at: 0)
        _ = animator.sample(at: 0.260)
        _ = animator.startClosing(at: 0.260)
        let beforeReverse = animator.sample(at: 0.350)

        let afterReverse = animator.reverse(at: 0.350)

        XCTAssertEqual(afterReverse, beforeReverse)
        XCTAssertEqual(animator.sample(at: 0.479).progress, 0.9961538, accuracy: 0.000001)
        XCTAssertFalse(animator.sample(at: 0.479).isComplete)
        XCTAssertEqual(animator.sample(at: 0.480).progress, 1, accuracy: 0.0000001)
        XCTAssertTrue(animator.sample(at: 0.480).isComplete)
    }

    func testReversalCannotDeliverALateClosingCompletion() {
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .topLeft,
            reducedMotion: false
        )
        var completedDirections: [PanelAnimationDirection] = []
        animator.onComplete = { completedDirections.append($0) }

        _ = animator.startOpening(at: 0)
        _ = animator.sample(at: 0.260)
        completedDirections.removeAll()
        _ = animator.startClosing(at: 0.260)
        _ = animator.sample(at: 0.350)
        _ = animator.reverse(at: 0.350)
        _ = animator.sample(at: 0.480)
        _ = animator.sample(at: 0.660)

        XCTAssertEqual(completedDirections, [.opening])
    }

    func testReducedMotionUses120MillisecondsWithoutOvershoot() {
        let finalFrame = CGRect(x: 108, y: 208, width: 320, height: 400)
        let animator = PanelAnimator(
            finalFrame: finalFrame,
            corner: .topLeft,
            reducedMotion: true
        )

        let start = animator.startOpening(at: 0)
        XCTAssertEqual(start.progress, 0, accuracy: 0.0000001)
        XCTAssertEqual(start.shellScale, 0.96, accuracy: 0.0000001)
        XCTAssertEqual(start.windowAlpha, 0, accuracy: 0.0000001)
        XCTAssertEqual(start.contentAlpha, 0, accuracy: 0.0000001)

        let midpoint = animator.sample(at: 0.060)
        XCTAssertEqual(midpoint.progress, 0.5, accuracy: 0.0000001)
        XCTAssertEqual(midpoint.shellScale, 0.98, accuracy: 0.0000001)
        XCTAssertEqual(midpoint.windowAlpha, 0.5, accuracy: 0.0000001)
        XCTAssertEqual(midpoint.contentAlpha, 0.5, accuracy: 0.0000001)
        XCTAssertEqual(midpoint.frame.minX, finalFrame.minX, accuracy: 0.0000001)
        XCTAssertEqual(midpoint.frame.maxY, finalFrame.maxY, accuracy: 0.0000001)

        let beforeEnd = animator.sample(at: 0.119)
        XCTAssertEqual(beforeEnd.progress, 119.0 / 120.0, accuracy: 0.0000001)
        XCTAssertFalse(beforeEnd.isComplete)
        XCTAssertLessThanOrEqual(beforeEnd.shellScale, 1)

        let end = animator.sample(at: 0.120)
        XCTAssertEqual(end.progress, 1, accuracy: 0.0000001)
        XCTAssertEqual(end.shellScale, 1, accuracy: 0.0000001)
        XCTAssertEqual(end.windowAlpha, 1, accuracy: 0.0000001)
        XCTAssertEqual(end.contentAlpha, 1, accuracy: 0.0000001)
        XCTAssertEqual(end.frame, finalFrame)

        for index in 0...1_000 {
            let time = Double(index) * 0.000120
            XCTAssertLessThanOrEqual(animator.sample(at: time).shellScale, 1.0)
        }
    }

    func testReducedMotionReversalAtHalfProgressFinishesOpeningAfter60Milliseconds() {
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .bottomRight,
            reducedMotion: true
        )

        _ = animator.startOpening(at: 0)
        _ = animator.sample(at: 0.120)
        _ = animator.startClosing(at: 0.120)
        let beforeReverse = animator.sample(at: 0.180)
        let afterReverse = animator.reverse(at: 0.180)

        XCTAssertEqual(beforeReverse.progress, 0.5, accuracy: 0.0000001)
        XCTAssertEqual(afterReverse, beforeReverse)
        XCTAssertEqual(animator.direction, .opening)
        XCTAssertEqual(animator.sample(at: 0.239).progress, 119.0 / 120.0, accuracy: 0.0000001)
        XCTAssertFalse(animator.sample(at: 0.239).isComplete)
        XCTAssertTrue(animator.sample(at: 0.240).isComplete)
        XCTAssertEqual(animator.progress, 1, accuracy: 0.0000001)
    }

    func testAnimationIgnoresBackwardsAndNonFiniteTime() {
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .topLeft,
            reducedMotion: true
        )

        _ = animator.startOpening(at: 0)
        let progressed = animator.sample(at: 0.060)

        XCTAssertEqual(animator.sample(at: 0.050), progressed)
        XCTAssertEqual(animator.sample(at: .nan), progressed)
        XCTAssertEqual(animator.sample(at: .infinity), progressed)
    }

    func testReverseAtBackwardsTimePreservesTheCurrentDirectionAndSample() {
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .topLeft,
            reducedMotion: true
        )

        _ = animator.startOpening(at: 0)
        _ = animator.sample(at: 0.120)
        _ = animator.startClosing(at: 0.120)
        let beforeReverse = animator.sample(at: 0.180)

        let afterReverse = animator.reverse(at: 0.170)

        XCTAssertEqual(afterReverse, beforeReverse)
        XCTAssertEqual(animator.direction, .closing)
        XCTAssertEqual(animator.progress, beforeReverse.progress, accuracy: 0.0000001)
    }
}

@MainActor
final class PanelTickerAndControllerTests: XCTestCase {
    func testPresentAndDismissKeepThePanelNonactivatingWithoutFocusRestoration() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )

        controller.present(screenID: screenID)
        XCTAssertTrue(controller.panel?.styleMask.contains(.nonactivatingPanel) == true)

        now = 0.120
        _ = controller.tick(at: now)
        controller.dismiss()
        now = 0.240
        _ = controller.tick(at: now)
        XCTAssertNil(controller.keepOpenFrame)
    }

    func testControllerExposesCurrentKeepOpenFrameOnlyWhileVisible() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )

        XCTAssertNil(controller.keepOpenFrame)
        controller.present(screenID: screenID)
        XCTAssertNotNil(controller.keepOpenFrame)

        now = 0.120
        _ = controller.tick(at: now)
        controller.dismiss()
        now = 0.240
        _ = controller.tick(at: now)

        XCTAssertNil(controller.keepOpenFrame)
    }

    func testCaptureTrackingAreaUsesBoundaryOptionsWithoutMouseMoved() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for panel behavior tests")
        }
        let screenID = Self.displayID(for: screen)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            reducedMotionProvider: { true }
        )

        controller.present(screenID: screenID)
        let area = try XCTUnwrap(controller.panel?.contentView?.trackingAreas.first)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertFalse(area.options.contains(.mouseMoved))
    }

    func testControllerHostsSuppliedContentInsideTrackedProbe() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for panel hosting tests")
        }
        let screenID = Self.displayID(for: screen)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            reducedMotionProvider: { true }
        )
        let hostedView = NSView()
        hostedView.setAccessibilityIdentifier("hosted.fixture")
        controller.installHostedContentFactory { hostedView }

        controller.present(screenID: screenID)

        let probe = try XCTUnwrap(controller.panel?.contentView)
        XCTAssertFalse(probe === hostedView)
        XCTAssertTrue(probe.subviews.contains { $0 === hostedView })
        XCTAssertEqual(hostedView.accessibilityIdentifier(), "hosted.fixture")
    }

    func testHostedContentDoesNotRemoveRequiredTrackingArea() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for panel hosting tests")
        }
        let screenID = Self.displayID(for: screen)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            reducedMotionProvider: { true }
        )
        controller.installHostedContentFactory { NSView() }

        controller.present(screenID: screenID)

        let probe = try XCTUnwrap(controller.panel?.contentView)
        let area = try XCTUnwrap(probe.trackingAreas.first)
        XCTAssertEqual(probe.subviews.count, 1)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertFalse(area.options.contains(.mouseMoved))
    }

    func testEscapeCloseReasonUsesCoordinatorEscapeBeforeDismiss() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel command tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var order: [String] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onEscape = { order.append("escape") }
        controller.onLifecycle = { event in
            if case .beganClosing = event {
                order.append("closing")
            }
        }
        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)

        controller.handleCaptureCommand(.close(.escape))

        XCTAssertEqual(order, ["escape", "closing"])
    }

    func testSubmittedOutsideCloseReasonDismissesWithoutEscapeSuppression() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel command tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var escapeCount = 0
        var beganClosing = false
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onEscape = { escapeCount += 1 }
        controller.onLifecycle = { event in
            if case .beganClosing = event {
                beganClosing = true
            }
        }
        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)

        controller.handleCaptureCommand(.close(.submittedOutside))

        XCTAssertEqual(escapeCount, 0)
        XCTAssertTrue(beganClosing)
    }

    func testCaptureBoundaryCallbackForwardsToCoordinatorHook() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var callbackCount = 0
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            reducedMotionProvider: { true }
        )
        controller.onPointerBoundaryChanged = { callbackCount += 1 }

        controller.present(screenID: screenID)

        XCTAssertGreaterThan(callbackCount, 0)
    }

    func testTickerStopsAtCompletionAndDeliversCompletionOnce() {
        var now: TimeInterval = 0
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .topLeft,
            reducedMotion: true,
            clock: { now }
        )
        var completedDirections: [PanelAnimationDirection] = []
        animator.onComplete = { completedDirections.append($0) }

        _ = animator.startOpening(at: 0)
        animator.startTicker()
        XCTAssertTrue(animator.isTickerRunning)

        now = 0.120
        _ = animator.tick(at: now)

        XCTAssertFalse(animator.isTickerRunning)
        XCTAssertEqual(completedDirections, [.opening])

        _ = animator.tick(at: 1.0)
        XCTAssertEqual(completedDirections, [.opening])
        animator.stopTicker()
    }

    func testCompletionObserverCanStartTheNextCycleWithoutLateTickerStop() {
        var now: TimeInterval = 0
        let animator = PanelAnimator(
            finalFrame: CGRect(x: 108, y: 208, width: 320, height: 400),
            corner: .topLeft,
            reducedMotion: true,
            clock: { now }
        )
        var startedClosing = false
        animator.onSample = { sample in
            guard sample.isComplete,
                  animator.direction == .opening,
                  !startedClosing else {
                return
            }
            startedClosing = true
            _ = animator.startClosing(at: now)
            animator.startTicker()
        }

        _ = animator.startOpening(at: 0)
        animator.startTicker()
        now = 0.120
        _ = animator.tick(at: now)

        XCTAssertTrue(startedClosing)
        XCTAssertTrue(animator.isTickerRunning)
        animator.stopTicker()
    }

    func testControllerKeepsLifecycleOrderAndIgnoresLateCloseTicks() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var events: [CapturePanelLifecycleEvent] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onLifecycle = { events.append($0) }

        controller.present(screenID: screenID)
        let panel = controller.panel
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(panel?.ignoresMouseEvents == true)
        XCTAssertEqual(events, [.beganOpening(screenID: screenID)])

        now = 0.120
        _ = controller.tick(at: now)
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID)
        ])
        XCTAssertFalse(panel?.ignoresMouseEvents == true)
        XCTAssertTrue(panel?.firstResponder === panel?.contentView)

        controller.dismiss()
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID),
            .beganClosing(screenID: screenID)
        ])

        now = 0.240
        _ = controller.tick(at: now)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(panel?.isVisible == true)
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID),
            .beganClosing(screenID: screenID),
            .didClose
        ])

        _ = controller.tick(at: 1.0)
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID),
            .beganClosing(screenID: screenID),
            .didClose
        ])
    }

    func testControllerDefersOpeningDismissAndReverses() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var events: [CapturePanelLifecycleEvent] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onLifecycle = { events.append($0) }

        controller.present(screenID: screenID)
        controller.dismiss()
        XCTAssertEqual(events, [.beganOpening(screenID: screenID)])

        now = 0.120
        _ = controller.tick(at: now)
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID),
            .beganClosing(screenID: screenID)
        ])

        now = 0.180
        _ = controller.tick(at: now)
        controller.reverseClosing(screenID: screenID)
        XCTAssertEqual(events.last, .beganOpening(screenID: screenID))

        now = 0.240
        _ = controller.tick(at: now)
        XCTAssertEqual(events.last, .didOpen(screenID: screenID))
        XCTAssertTrue(controller.isVisible)

        controller.dismiss()
        now = 0.360
        _ = controller.tick(at: now)

        XCTAssertEqual(events.last, .didClose)
    }

    func testOpeningDismissThenReentryBeforeCompletionKeepsPanelOpen() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var events: [CapturePanelLifecycleEvent] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onLifecycle = { events.append($0) }

        controller.present(screenID: screenID)
        controller.dismiss()
        now = 0.060
        _ = controller.tick(at: now)
        controller.reverseClosing(screenID: screenID)

        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .beganOpening(screenID: screenID)
        ])

        now = 0.120
        _ = controller.tick(at: now)

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID)
        ])

        now = 0.300
        _ = controller.tick(at: now)
        XCTAssertFalse(events.contains { event in
            if case .beganClosing = event { return true }
            if case .didClose = event { return true }
            return false
        })
    }

    func testControllerAppliesReversalSampleBeforeTheNextTicker() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        let defaults = UserDefaults(suiteName: "CornerPet.PanelTickerAndControllerTests.\(UUID().uuidString)")!
        let store = PinnedPanelSizeStore(defaults: defaults)
        var events: [CapturePanelLifecycleEvent] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true },
            pinnedSizeStore: store
        )
        controller.onLifecycle = { events.append($0) }

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        controller.dismiss()

        now = 0.180
        _ = controller.tick(at: now)
        guard let panel = controller.panel else {
            XCTFail("Presenting the panel must create a panel")
            return
        }
        let frameBeforeReverse = panel.frame

        let finalFrame = PanelPositioner.frame(
            inside: screen.visibleFrame,
            corner: .topLeft
        )
        let expectedAnimator = PanelAnimator(
            finalFrame: finalFrame,
            corner: .topLeft,
            reducedMotion: true
        )
        _ = expectedAnimator.startOpening(at: 0)
        _ = expectedAnimator.sample(at: 0.120)
        _ = expectedAnimator.startClosing(at: 0.120)
        _ = expectedAnimator.sample(at: 0.180)
        let expectedAtReverse = expectedAnimator.reverse(at: 0.200)

        now = 0.200
        controller.reverseClosing(screenID: screenID)

        XCTAssertNotEqual(panel.frame, frameBeforeReverse)
        // NSPanel aligns its frame to screen pixels when it is rendered. The
        // controller must still apply the reversal sample immediately; compare
        // with the frame AppKit can actually display rather than the animator's
        // sub-pixel calculation.
        XCTAssertEqual(panel.frame, expectedAtReverse.frame.integral)
        XCTAssertEqual(panel.alphaValue, expectedAtReverse.windowAlpha, accuracy: 0.0000001)
        XCTAssertEqual(
            panel.contentView?.alphaValue ?? -1,
            expectedAtReverse.contentAlpha,
            accuracy: 0.0000001
        )
        XCTAssertEqual(events, [
            .beganOpening(screenID: screenID),
            .didOpen(screenID: screenID),
            .beganClosing(screenID: screenID),
            .beganOpening(screenID: screenID)
        ])
    }

    func testFocusedLocalEscapeProbeDismissesThePanel() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var events: [CapturePanelLifecycleEvent] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onLifecycle = { events.append($0) }

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        guard let panel = controller.panel,
              let escape = NSEvent.keyEvent(
                  with: .keyDown,
                  location: .zero,
                  modifierFlags: [],
                  timestamp: now,
                  windowNumber: panel.windowNumber,
                  context: nil,
                  characters: "\u{1b}",
                  charactersIgnoringModifiers: "\u{1b}",
                  isARepeat: false,
                  keyCode: 53
              ) else {
            XCTFail("The opened panel must provide a local Escape event target")
            return
        }

        panel.contentView?.keyDown(with: escape)

        XCTAssertEqual(events.last, .beganClosing(screenID: screenID))
        now = 0.240
        _ = controller.tick(at: now)
        XCTAssertEqual(events.last, .didClose)
    }

    func testEscapeForwardsToCoordinatorBeforeDismissLifecycle() {
        guard let screen = NSScreen.screens.first else {
            XCTFail("A screen is required for panel behavior tests")
            return
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var order: [String] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onEscape = { order.append("escape") }
        controller.onLifecycle = { event in
            if case .beganClosing = event {
                order.append("closing")
            }
        }

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        guard let panel = controller.panel,
              let escape = NSEvent.keyEvent(
                  with: .keyDown,
                  location: .zero,
                  modifierFlags: [],
                  timestamp: now,
                  windowNumber: panel.windowNumber,
                  context: nil,
                  characters: "\u{1b}",
                  charactersIgnoringModifiers: "\u{1b}",
                  isARepeat: false,
                  keyCode: 53
              ) else {
            XCTFail("The opened panel must provide a local Escape event target")
            return
        }

        panel.contentView?.keyDown(with: escape)

        XCTAssertEqual(order, ["escape", "closing"])
    }

    func testWindowResignKeyForwardsExternalFocusBeforeAnyDismissal() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for external-focus tests")
        }
        let screenID = Self.displayID(for: screen)
        var now: TimeInterval = 0
        var focusLossCount = 0
        var lifecycleEvents: [CapturePanelLifecycleEvent] = []
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        controller.onExternalFocusLost = { focusLossCount += 1 }
        controller.onLifecycle = { lifecycleEvents.append($0) }

        controller.present(screenID: screenID)
        now = 0.120
        _ = controller.tick(at: now)
        let panel = try XCTUnwrap(controller.panel)

        controller.windowDidResignKey(Notification(
            name: NSWindow.didResignKeyNotification,
            object: panel
        ))

        XCTAssertEqual(focusLossCount, 1)
        XCTAssertFalse(lifecycleEvents.contains { event in
            if case .beganClosing = event { return true }
            return false
        })
        XCTAssertTrue(controller.isVisible)
    }

    func testCommandShiftPReachesOneControllerTogglePath() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for shortcut tests")
        }
        let screenID = Self.displayID(for: screen)
        let controller = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            reducedMotionProvider: { true }
        )
        var toggleCount = 0
        controller.onTogglePin = { toggleCount += 1 }

        controller.present(screenID: screenID)
        _ = controller.tick(at: 0.120)
        let panel = try XCTUnwrap(controller.panel)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0.120,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "p",
            charactersIgnoringModifiers: "p",
            isARepeat: false,
            keyCode: 35
        ))

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(toggleCount, 1)
    }

    func testCommandFFromNonactivatingPanelInvokesFindRoute() throws {
        let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))
        var findCount = 0
        panel.onFind = {
            findCount += 1
            return true
        }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0.120,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "f",
            charactersIgnoringModifiers: "f",
            isARepeat: false,
            keyCode: 3
        ))

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(findCount, 1)
    }

    func testCommandCommaFromCornerPanelPerformsTheSettingsMenuCommand() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let actionSpy = SettingsMenuActionSpy()
        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(SettingsMenuActionSpy.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = actionSpy
        let menu = NSMenu()
        menu.addItem(settingsItem)
        NSApp.mainMenu = menu

        let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0.120,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        ))

        panel.sendEvent(event)
        Self.waitForSettingsAction(actionSpy)
        XCTAssertEqual(actionSpy.openSettingsCallCount, 1)
    }

    func testCommandCommaUsesCharacterSemanticsAcrossKeyboardLayouts() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let actionSpy = SettingsMenuActionSpy()
        NSApp.mainMenu = Self.settingsMenu(target: actionSpy)
        let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))
        let event = try XCTUnwrap(Self.keyEvent(
            characters: ",",
            modifiers: [.command],
            keyCode: 0,
            windowNumber: panel.windowNumber
        ))

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        Self.waitForSettingsAction(actionSpy)
        XCTAssertEqual(actionSpy.openSettingsCallCount, 1)
    }

    func testCommandCommaAllowsCapsLockModifier() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let actionSpy = SettingsMenuActionSpy()
        NSApp.mainMenu = Self.settingsMenu(target: actionSpy)
        let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))
        let event = try XCTUnwrap(Self.keyEvent(
            characters: ",",
            modifiers: [.command, .capsLock],
            keyCode: 43,
            windowNumber: panel.windowNumber
        ))

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        Self.waitForSettingsAction(actionSpy)
        XCTAssertEqual(actionSpy.openSettingsCallCount, 1)
    }

    func testCommandKeyCode43WithoutCommaDoesNotPerformSettingsCommand() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let actionSpy = SettingsMenuActionSpy()
        NSApp.mainMenu = Self.settingsMenu(target: actionSpy)
        let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))
        let event = try XCTUnwrap(Self.keyEvent(
            characters: ".",
            modifiers: [.command],
            keyCode: 43,
            windowNumber: panel.windowNumber
        ))

        XCTAssertFalse(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(actionSpy.openSettingsCallCount, 0)
    }

    private static func settingsMenu(target: SettingsMenuActionSpy) -> NSMenu {
        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(SettingsMenuActionSpy.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = target
        let menu = NSMenu()
        menu.addItem(settingsItem)
        return menu
    }

    private static func waitForSettingsAction(_ actionSpy: SettingsMenuActionSpy) {
        let deadline = Date().addingTimeInterval(1)
        while actionSpy.openSettingsCallCount == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private static func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16,
        windowNumber: Int
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0.120,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private static func displayID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private final class SettingsMenuActionSpy: NSObject {
    private(set) var openSettingsCallCount = 0

    @objc func openSettings(_ sender: Any?) {
        openSettingsCallCount += 1
    }
}

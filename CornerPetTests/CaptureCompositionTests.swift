import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import CornerPet

@MainActor
final class CaptureCompositionTests: XCTestCase {
    func testDidOpenRestoresDraftAndRequestsInputFocus() async throws {
        let (screen, screenID) = try mainScreen()
        let container = try ModelContainerFactory.makeInMemory()
        let seedStore = DraftStore(context: container.mainContext)
        seedStore.stage(text: "A🐱 saved draft", updatedAt: Date(timeIntervalSince1970: 10))
        try seedStore.flush()

        var now: TimeInterval = 0
        let panelController = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        let coordinator = makeCoordinator(screen: screen, panelController: panelController)
        var composition: CaptureCompositionRoot?
        let appDelegate = AppDelegate(
            panelControllerFactory: { panelController },
            triggerCoordinatorFactory: { _ in coordinator },
            compositionFactory: { controller in
                let root = CaptureCompositionRoot(
                    container: container,
                    panelController: controller
                )
                composition = root
                return root
            }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        panelController.present(screenID: screenID)
        await Task.yield()
        now = 0.120
        _ = panelController.tick(at: now)
        await Task.yield()
        await Task.yield()

        let root = try XCTUnwrap(composition)
        let textView: CaptureTextView = try XCTUnwrap(
            descendant(of: panelController.panel?.contentView, as: CaptureTextView.self)
        )
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        XCTAssertEqual(root.captureViewModel.draftText, "A🐱 saved draft")
        XCTAssertTrue(panelController.panel?.firstResponder === textView)
        XCTAssertGreaterThan(textView.frame.width, 0)
        XCTAssertGreaterThan(textView.frame.height, 0)
        XCTAssertEqual(
            scrollView.frame.height,
            CaptureLayout.inputMinimumHeight,
            accuracy: 0.5
        )
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: "A🐱 saved draft".utf16.count, length: 0)
        )
    }

    func testTerminationFlushesDraftBeforeCoordinatorStops() throws {
        let (screen, _) = try mainScreen()
        let panelController = CapturePanelController(screenProvider: { _ in nil })
        let coordinator = makeCoordinator(screen: screen, panelController: panelController)
        let container = try ModelContainerFactory.makeInMemory()
        var coordinatorWasRunningDuringFlush = false
        let spy = try CompositionSpy(container: container) {
            coordinatorWasRunningDuringFlush = coordinator.isRunning
        }
        let appDelegate = AppDelegate(
            panelControllerFactory: { panelController },
            triggerCoordinatorFactory: { _ in coordinator },
            compositionFactory: { _ in spy }
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        spy.captureViewModel.draftDidChange("flush me")
        XCTAssertTrue(coordinator.isRunning)

        appDelegate.applicationWillTerminate(Notification(name: .init("test")))

        XCTAssertTrue(coordinatorWasRunningDuringFlush)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(try spy.draftStore.restore().text, "flush me")
    }

    func testCompositionConnectsCreatedItemToInboxExactlyOnce() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let panelController = CapturePanelController(screenProvider: { _ in nil })
        let composition = CaptureCompositionRoot(
            container: container,
            panelController: panelController
        )
        composition.inboxViewModel.load()
        composition.captureViewModel.draftDidChange("one captured idea")

        _ = composition.captureViewModel.handleReturn(isShiftPressed: false)

        XCTAssertEqual(composition.inboxViewModel.items.map(\.text), ["one captured idea"])
        XCTAssertEqual(try composition.itemStore.fetchInbox().map(\.text), ["one captured idea"])
    }

    func testCompositionReportsDraftAndEditActivityForLifecycle() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let panelController = CapturePanelController(screenProvider: { _ in nil })
        let composition = CaptureCompositionRoot(
            container: container,
            panelController: panelController
        )
        let item = try XCTUnwrap(
            composition.itemStore.createInboxItem(
                text: "edit protection",
                at: Date(timeIntervalSince1970: 1)
            )
        )
        XCTAssertTrue(composition.editViewModel.beginEditing(item))
        XCTAssertTrue(composition.isAutoHideProtected)
        composition.editViewModel.cancel()
        XCTAssertFalse(composition.isAutoHideProtected)
    }

    func testExternalFocusAdapterSavesSharedEditBeforeLifecycleClose() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let panelController = CapturePanelController(screenProvider: { _ in nil })
        let composition = CaptureCompositionRoot(
            container: container,
            panelController: panelController
        )
        let item = try XCTUnwrap(
            composition.itemStore.createInboxItem(
                text: "before external focus",
                at: Date(timeIntervalSince1970: 1)
            )
        )

        XCTAssertTrue(composition.editViewModel.beginEditing(item))
        composition.editViewModel.setWorkingText("saved before close")

        let result = composition.saveActiveEditForExternalFocus()

        guard case let .saved(saved) = result else {
            return XCTFail("External focus must save the active shared editor")
        }
        XCTAssertEqual(saved.text, "saved before close")
        XCTAssertFalse(composition.editViewModel.isEditing)
        XCTAssertEqual(try composition.itemStore.fetchInbox().first?.text, "saved before close")
    }

    func testExternalFocusFailedEditSaveKeepsErrorEditorAndFirstResponderVisible() async throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("A screen is required for external-focus integration tests")
        }
        let screenID = try XCTUnwrap(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
        let container = try ModelContainerFactory.makeInMemory()
        let seedStore = ItemStore(context: container.mainContext)
        let item = try XCTUnwrap(
            seedStore.createInboxItem(
                text: "before failed focus save",
                at: Date(timeIntervalSince1970: 1)
            )
        )
        let failingStore = ExternalFocusFailingLifecycleStore(item: item)
        var now: TimeInterval = 0
        let panelController = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        let scheduler = ManualDeadlineScheduler()
        var composition: CaptureCompositionRoot?
        let appDelegate = AppDelegate(
            panelControllerFactory: { panelController },
            triggerCoordinatorFactory: { _ in
                CornerTriggerCoordinator(
                    screenProvider: { screen },
                    clock: { now },
                    pointerLocationProvider: {
                        CGPoint(x: screen.frame.midX, y: screen.frame.midY)
                    },
                    scheduler: ManualDeadlineScheduler(),
                    presentPanel: { _ in },
                    reverseClosingPanel: { _ in }
                )
            },
            compositionFactory: { controller in
                let root = CaptureCompositionRoot(
                    container: container,
                    panelController: controller,
                    itemLifecycleStore: failingStore
                )
                composition = root
                return root
            },
            lifecycleCoordinatorFactory: { controller in
                PanelLifecycleCoordinator(
                    panelController: controller,
                    scheduler: scheduler,
                    clock: { now },
                    pointerInsideKeepOpen: { true }
                )
            }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))
        let root = try XCTUnwrap(composition)
        XCTAssertTrue(root.editViewModel.beginEditing(item))
        root.editViewModel.setWorkingText("working text must remain")

        appDelegate.lifecycleCoordinator?.presentRequested(screenID: screenID)
        panelController.present(screenID: screenID)
        await Task.yield()
        now = 0.120
        _ = panelController.tick(at: now)
        for _ in 0..<4 {
            await Task.yield()
        }

        let panel = try XCTUnwrap(panelController.panel)
        let editor = try XCTUnwrap(
            descendant(of: panel.contentView, as: InlineItemTextView.self)
        )
        XCTAssertTrue(panel.makeFirstResponder(editor))
        XCTAssertTrue(panel.firstResponder === editor)

        panelController.windowDidResignKey(Notification(
            name: NSWindow.didResignKeyNotification,
            object: panel
        ))

        XCTAssertEqual(failingStore.updateAttemptCount, 1)
        XCTAssertEqual(root.editViewModel.error, .saveFailed)
        XCTAssertTrue(root.editViewModel.isEditing)
        XCTAssertEqual(root.editViewModel.workingText, "working text must remain")
        XCTAssertEqual(editor.string, "working text must remain")
        XCTAssertTrue(panelController.isVisible)
        XCTAssertTrue(panel.firstResponder === editor)
        XCTAssertEqual(appDelegate.lifecycleCoordinator?.state, .error)

        root.editViewModel.dismissError()
        XCTAssertEqual(appDelegate.lifecycleCoordinator?.state, .itemEditing)
        XCTAssertTrue(root.editViewModel.isEditing)
        XCTAssertEqual(root.editViewModel.workingText, "working text must remain")
    }

    func testAppDelegateCreatesLifecycleCoordinator() throws {
        let (screen, _) = try mainScreen()
        let panelController = CapturePanelController(screenProvider: { _ in nil })
        let coordinator = makeCoordinator(screen: screen, panelController: panelController)
        let container = try ModelContainerFactory.makeInMemory()
        let spy = try CompositionSpy(container: container, onTerminate: {})
        spy.setAutoHideProtected(true)
        let appDelegate = AppDelegate(
            panelControllerFactory: { panelController },
            triggerCoordinatorFactory: { _ in coordinator },
            compositionFactory: { _ in spy }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        XCTAssertNotNil(appDelegate.lifecycleCoordinator)
    }

    func testConfiguredCompositionRoutesPanelShortcutThroughPinHandler() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let screenID = try XCTUnwrap(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
        var now: TimeInterval = 0
        let panelController = CapturePanelController(
            screenProvider: { requestedID in
                requestedID == screenID ? screen : nil
            },
            clock: { now },
            reducedMotionProvider: { true }
        )
        let container = try ModelContainerFactory.makeInMemory()
        let composition = CaptureCompositionRoot(
            container: container,
            panelController: panelController
        )
        var toggleCount = 0
        composition.configurePanelPinning(
            isPinned: { false },
            onTogglePin: { toggleCount += 1 }
        )

        panelController.present(screenID: screenID)
        now = 0.120
        _ = panelController.tick(at: now)
        let panel = try XCTUnwrap(panelController.panel)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: now,
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

    private func mainScreen() throws -> (NSScreen, UInt32) {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let screenID = try XCTUnwrap(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
        return (screen, screenID)
    }

    private func makeCoordinator(
        screen: NSScreen,
        panelController: CapturePanelController
    ) -> CornerTriggerCoordinator {
        CornerTriggerCoordinator(
            screenProvider: { screen },
            clock: { 0 },
            pointerLocationProvider: { CGPoint(x: screen.frame.midX, y: screen.frame.midY) },
            scheduler: ManualDeadlineScheduler(),
            presentPanel: { _ in },
            reverseClosingPanel: { _ in }
        )
    }

    private func descendant<T: NSView>(of root: NSView?, as type: T.Type) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for child in root.subviews {
            if let match = descendant(of: child, as: type) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private final class CompositionSpy: CaptureComposing {
    let captureViewModel: CaptureViewModel
    let draftStore: DraftStore

    private(set) var isAutoHideProtected = false
    var onAutoHideProtectionChanged: ((Bool) -> Void)?

    private let onTerminate: () -> Void

    init(container: ModelContainer, onTerminate: @escaping () -> Void) throws {
        let draftStore = DraftStore(context: container.mainContext)
        let itemStore = ItemStore(context: container.mainContext)
        self.draftStore = draftStore
        captureViewModel = CaptureViewModel(
            draftStore: draftStore,
            itemStore: itemStore,
            pointerInsidePanel: { false },
            isPinned: { false }
        )
        self.onTerminate = onTerminate
    }

    func makeRootView() -> AnyView {
        AnyView(EmptyView())
    }

    func applicationWillTerminate() {
        onTerminate()
        captureViewModel.flushDraft()
    }

    func setAutoHideProtected(_ isProtected: Bool) {
        isAutoHideProtected = isProtected
        onAutoHideProtectionChanged?(isProtected)
    }
}

@MainActor
private final class ExternalFocusFailingLifecycleStore: ItemLifecycleStoring {
    private let item: IdeaItemSnapshot
    private(set) var updateAttemptCount = 0

    init(item: IdeaItemSnapshot) {
        self.item = item
    }

    func createInboxItem(text: String, at date: Date) throws -> IdeaItemSnapshot? {
        nil
    }

    func fetchInbox() throws -> [IdeaItemSnapshot] {
        [item]
    }

    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot] {
        bucket == item.bucket ? [item] : []
    }

    func moveItem(
        id: UUID,
        from source: ItemBucket,
        to destination: ItemBucket,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        nil
    }

    func updateItemText(
        id: UUID,
        expectedBucket: ItemBucket,
        text: String,
        at date: Date
    ) throws -> IdeaItemSnapshot? {
        updateAttemptCount += 1
        throw ExternalFocusStoreError.saveFailed
    }

    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool {
        false
    }
}

private enum ExternalFocusStoreError: Error {
    case saveFailed
}

# Task 7 Capture-first Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Luna max implements each UI/integration slice; Terra high performs code, behavior, and visual acceptance before Task 7 is reported complete.

**Goal:** Deliver the first usable 360×450 capture panel: fixed bilingual header, one-to-five-line focused input, independently scrolling newest-first inbox, persistent save error, and fixed bilingual bottom navigation with non-business placeholders for Favorites, Archive, and Settings.

**Architecture:** A SwiftUI capture shell renders Task 6 observable state and a dedicated `InboxViewModel`; an `NSViewRepresentable` text editor owns AppKit key/selection/IME behavior. `CapturePanelController` hosts the shell inside its existing tracked probe view, and `AppDelegate` composes the Task 5 container/stores with Task 6/7 view models without moving persistence or window policy into views.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSHostingView`, `NSTextView`, `NSScrollView`), SwiftData through Task 5 stores, Observation, XCTest, XCUITest; no third-party dependencies

**Spec:** `docs/superpowers/specs/2026-08-25-hot-corner-capture-interaction-design.md`

## Global Constraints

- Execute only after Task 6 passes Terra high review; do not rename or bypass its stable interfaces without first updating Task 6 tests and plan handoff.
- Work in `/Users/jack/MyApp/CornerPet`; preserve every existing dirty-worktree change.
- Do not commit, push, create a PR, discard, regenerate, or blanket-revert. Every commit-like boundary is a checkpoint waiting for Jack's explicit authorization.
- Minimum platform is macOS 14 Sonoma; Apple Silicon arm64 only; Swift 6; AppKit + SwiftUI + SwiftData; local-only; no account, network, cloud sync, or third-party package.
- Preserve fixed 0.400-second dwell, exact `86×20 + 20×86 pt` main-screen top-left trigger panels, and 0.100-second trigger-plus-capture keep-open close debounce.
- Preserve the default panel at exactly 360×450 pt, `edgeInset == 0`, flush with the screen left edge and menu bar lower edge.
- Preserve existing 260/180 ms reversible animation and 120 ms Reduce Motion path; do not change trigger, panel size, or animation constants for layout convenience.
- Header, capture input, error region, and bottom navigation are fixed. Only the inbox/list-or-placeholder middle region scrolls or changes destination.
- Capture input starts at one visible line, grows through five visible lines, then scrolls internally with no artificial content-length limit.
- Inbox is newest-first and scrolls independently. A successful new item appears at index 0 without closing/reopening when policy says keep open.
- Bottom navigation uses fixed bilingual copy: `收件箱 / Inbox`, `收藏 / Favorites`, `归档 / Archive`, `设置 / Settings`.
- Favorites, Archive, and Settings destinations are navigation-state placeholders only. Do not add search, archive, favorite, edit, undo, delete, settings persistence, pin movement/resizing, or their production business logic.
- The header includes a pin affordance, but until Task 9 it only reflects/invokes an injected availability/state contract; it must not claim the window is pinned when no pin controller exists.
- Save errors never cover the input and remain visible until retry, success, or explicit dismissal. Input remains usable during list-load failure.
- Shift-Return must preserve `NSTextView` selection/IME semantics and insert a newline. Return submits only when there is no active marked-text composition. Escape preserves the draft.
- Use the Xcode beta `DEVELOPER_DIR` override per command; never change global `xcode-select`.
- Maintain explicit PBX references and target memberships; do not regenerate the project or alter signing settings.

---

## Task 6 Entry Gate

Run exactly:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected: all Task 1–6 tests pass. If not, return the defect to the owning earlier slice before any Task 7 UI edit.

## File Responsibility Map

| File | Responsibility |
|---|---|
| `CornerPet/Capture/CaptureDestination.swift` | Destination enum, bilingual labels, icons, and placeholder metadata |
| `CornerPet/Capture/CaptureShellViewModel.swift` | Selected destination and placeholder navigation state only |
| `CornerPet/Capture/InboxViewModel.swift` | Newest-first inbox load/retry/prepend and list-only error state |
| `CornerPet/Capture/CaptureTextEditor.swift` | `NSTextView` bridge, 1–5-line measurement, scrolling, key handling, focus-at-end |
| `CornerPet/Capture/CapturePanelView.swift` | Fixed shell composition and command adaptation |
| `CornerPet/Capture/CaptureHeaderView.swift` | Cat status, bilingual product identity, truthful pin affordance |
| `CornerPet/Capture/InboxView.swift` | Independently scrolling inbox/list-error/empty states |
| `CornerPet/Capture/ItemRow.swift` | Read-only Task 7 row rendering; lifecycle controls are visual-only until Task 8 |
| `CornerPet/Capture/CaptureNavigationBar.swift` | Fixed bilingual four-destination selection |
| `CornerPet/Capture/CaptureCompositionRoot.swift` | Container/store/view-model/view composition and draft lifecycle flush |
| `CornerPet/Panel/CapturePanelController.swift` | Host supplied SwiftUI content inside existing tracked probe; adapt close reason |
| `CornerPet/App/AppDelegate.swift` | Build production composition and connect panel lifecycle/commands |
| `CornerPetTests/CaptureLayoutTests.swift` | Exact layout metrics, labels, destination state, input-height policy |
| `CornerPetTests/InboxViewModelTests.swift` | Sort/load/prepend/retry and list-error isolation |
| `CornerPetTests/CaptureCompositionTests.swift` | Real-store/panel composition and lifecycle wiring |
| `CornerPetTests/PanelAnimatorTests.swift` | Regression for hosted content, tracking, focus, and Escape path |
| `CornerPetUITests/CaptureFlowUITests.swift` | Launch-open capture, input/submission/newline/error shell/navigation flow |
| `CornerPet.xcodeproj/project.pbxproj` | Explicit product/unit/UI-test file references and source memberships |

## Stable Task 7 Interfaces

```swift
enum CaptureDestination: String, CaseIterable, Identifiable {
    case inbox
    case favorites
    case archive
    case settings

    var id: String { rawValue }
    var chineseTitle: String { get }
    var englishTitle: String { get }
    var systemImage: String { get }
}

enum CaptureLayout {
    static let panelSize = CGSize(width: 360, height: 450)
    static let outerPadding: CGFloat = 12
    static let headerHeight: CGFloat = 42
    static let navigationHeight: CGFloat = 54
    static let inputMinimumHeight: CGFloat = 30
    static let inputMaximumHeight: CGFloat = 110
    static let inputVisibleLineLimit = 5

    static func inputHeight(contentHeight: CGFloat) -> CGFloat
}

@MainActor
@Observable
final class CaptureShellViewModel {
    private(set) var selectedDestination: CaptureDestination = .inbox
    func select(_ destination: CaptureDestination)
}

enum InboxLoadError: Equatable { case loadFailed }

@MainActor
@Observable
final class InboxViewModel {
    private(set) var items: [IdeaItemSnapshot] = []
    private(set) var loadError: InboxLoadError?

    init(itemStore: any ItemStoring)
    func load()
    func retryLoad()
    func prepend(_ item: IdeaItemSnapshot)
}

struct CaptureTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let focusRequest: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void
}

struct CapturePanelView: View {
    init(
        captureViewModel: CaptureViewModel,
        inboxViewModel: InboxViewModel,
        shellViewModel: CaptureShellViewModel,
        pinState: @escaping () -> Bool,
        pinAvailable: Bool,
        onTogglePin: @escaping () -> Void,
        onPanelCommand: @escaping (CapturePanelCommand) -> Void
    )
}

@MainActor
final class CaptureCompositionRoot {
    let container: ModelContainer
    let draftStore: DraftStore
    let itemStore: ItemStore
    let captureViewModel: CaptureViewModel
    let inboxViewModel: InboxViewModel
    let shellViewModel: CaptureShellViewModel

    init(container: ModelContainer, panelController: CapturePanelController)
    func makeRootView() -> AnyView
    func applicationWillTerminate()
}
```

Task 6's accepted close command carries a reason so Escape and successful outside submission do not share trigger suppression behavior:

```swift
enum CaptureCloseReason: Equatable {
    case escape
    case submittedOutside
}

enum CapturePanelCommand: Equatable {
    case focusInputAtEnd
    case close(CaptureCloseReason)
}
```

Task 6 tests already require Escape to emit `.close(.escape)` and outside success to emit `.close(.submittedOutside)`. The Task 7 adapter routes Escape through the controller's existing `onEscape` path and routes submission through ordinary `dismiss()`.

## Visual Contract at 360×450

```text
┌────────────────────────────────────┐  fixed 42 pt header
│  ●  CornerPet / 角落灵感箱      pin │
├────────────────────────────────────┤
│  capture input: 30...110 pt         │  1–5 lines, then internal scroll
├────────────────────────────────────┤
│  compact save error, when present   │  never overlays input
├────────────────────────────────────┤
│                                    │
│  inbox or destination placeholder  │  only this region scrolls/changes
│                                    │
├────────────────────────────────────┤
│ 收件箱   收藏    归档     设置       │  fixed 54 pt navigation
│ Inbox  Favorites Archive Settings  │
└────────────────────────────────────┘
```

---

### Task 7.1: Lock layout metrics, bilingual destinations, and navigation state

**Files:**

- Create: `CornerPet/Capture/CaptureDestination.swift`
- Create: `CornerPet/Capture/CaptureShellViewModel.swift`
- Create: `CornerPetTests/CaptureLayoutTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: exact panel size from `PanelPositioner.defaultSize`.
- Produces: `CaptureDestination`, `CaptureLayout`, and `CaptureShellViewModel`.

- [ ] **Step 1: Write metric and copy RED tests**

```swift
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

    func testDestinationsHaveExactBilingualCopy() {
        XCTAssertEqual(CaptureDestination.allCases.map(\.chineseTitle), ["收件箱", "收藏", "归档", "设置"])
        XCTAssertEqual(CaptureDestination.allCases.map(\.englishTitle), ["Inbox", "Favorites", "Archive", "Settings"])
    }

    func testShellStartsAtInboxAndStoresPlaceholderSelection() {
        let model = CaptureShellViewModel()
        XCTAssertEqual(model.selectedDestination, .inbox)
        model.select(.archive)
        XCTAssertEqual(model.selectedDestination, .archive)
    }
}
```

- [ ] **Step 2: Add explicit memberships and verify compile RED**

Create the Capture PBX entries with new IDs, run `build-for-testing`, and expect missing Task 7 types.

- [ ] **Step 3: Implement constants and state minimally**

Use SF Symbols `tray`, `star`, `archivebox`, and `gearshape`. `inputHeight` is `min(inputMaximumHeight, max(inputMinimumHeight, contentHeight))`. Selection mutates only `selectedDestination`; it does not fetch archive/favorite/settings data.

- [ ] **Step 4: Run direct XCTest to GREEN and checkpoint**

Run the exact entry-gate workflow. Expected: all four Task 7.1 tests pass. Do not commit.

---

### Task 7.2: Implement newest-first inbox state with isolated load errors

**Files:**

- Create: `CornerPet/Capture/InboxViewModel.swift`
- Create: `CornerPetTests/InboxViewModelTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `ItemStoring.fetchInbox()` and created-item snapshots from `CaptureViewModel.onItemCreated`.
- Produces: `InboxViewModel` stable interface.

- [ ] **Step 1: Write inbox RED tests**

```swift
func testLoadPublishesStoreOrderAndClearsPreviousError()
func testLoadFailureReplacesOnlyListStateWithRetryableError()
func testRetryLoadsItemsAfterFailure()
func testPrependPlacesNewItemAtZeroWithoutRefetch()
func testPrependSameIDReplacesInsteadOfDuplicatingVisibleRow()
func testPrependPreservesNewestFirstOrderForOutOfOrderCallback()
```

For ordering, use snapshots at dates 10, 20, and 30 and assert `[30, 20, 10]`. `prepend` removes any same-ID snapshot, appends the incoming value, then sorts by `createdAt` descending and `id.uuidString` ascending for ties.

- [ ] **Step 2: Add memberships and run RED**

Expected: compile fails because `InboxViewModel` is absent.

- [ ] **Step 3: Implement load, retry, and prepend**

On load failure, retain no stale success claim: set `items = []`, set `.loadFailed`, and do not mutate `CaptureViewModel`. `retryLoad()` calls the same private loader. No archive/favorite/delete/edit method is allowed.

- [ ] **Step 4: Run direct XCTest to GREEN and checkpoint**

Expected: all six inbox tests pass; no SwiftUI/AppKit import in the view model. Do not commit.

---

### Task 7.3: Build the one-to-five-line AppKit text editor bridge

**Files:**

- Create: `CornerPet/Capture/CaptureTextEditor.swift`
- Add tests to: `CornerPetTests/CaptureLayoutTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: text binding, height binding, focus revision, submit/Escape closures.
- Produces: selection-safe Return/Shift-Return/Escape and measured scroll behavior.

- [ ] **Step 1: Add bridge RED tests around an exposed internal editor subclass**

Create `CaptureTextView: NSTextView` as module-internal so tests can instantiate it. Add:

```swift
func testPlainReturnCallsSubmitWithoutInsertingNewline()
func testShiftReturnUsesNativeNewlineInsertion()
func testEscapeCallsEscapeHandler()
func testReturnDuringMarkedTextUsesNativeTextHandling()
func testFocusRequestMovesSelectionToUTF16End()
func testScrollerEnablesOnlyAboveFiveLineMaximum()
```

Use synthesized key events with key codes 36 and 53. For marked-text behavior, install marked text through `setMarkedText(_:selectedRange:replacementRange:)` before Return and assert submit count stays zero.

- [ ] **Step 2: Add the product reference and run RED**

Expected: missing `CaptureTextEditor`/`CaptureTextView` compile errors.

- [ ] **Step 3: Implement the editor and coordinator**

Required AppKit configuration:

```swift
textView.isRichText = false
textView.isAutomaticQuoteSubstitutionEnabled = false
textView.isAutomaticDashSubstitutionEnabled = false
textView.allowsUndo = true
textView.isVerticallyResizable = true
textView.isHorizontallyResizable = false
textView.textContainer?.widthTracksTextView = true
scrollView.hasVerticalScroller = measuredContentHeight > CaptureLayout.inputMaximumHeight
scrollView.drawsBackground = false
```

Key rules in `CaptureTextView.keyDown(with:)`:

1. If `hasMarkedText()`, call `super` for every key.
2. Plain Return/keypad Enter invokes submit and does not call `super`.
3. Shift-Return/keypad Enter calls `insertNewlineIgnoringFieldEditor(self)` so native selection replacement remains correct.
4. Escape invokes the escape closure.
5. Other keys call `super`.

The coordinator updates the binding from `textDidChange`, measures `layoutManager.usedRect(for:)` plus text-container inset, clamps through `CaptureLayout.inputHeight`, and dispatches binding writes to the next main-run-loop turn to avoid mutating SwiftUI during update. On a new `focusRequest`, call `window?.makeFirstResponder(textView)` and set `selectedRange = NSRange(location: textView.string.utf16.count, length: 0)`.

- [ ] **Step 4: Run direct XCTest and inspect no artificial limit**

Run the direct workflow, then:

```bash
if rg -n 'maxLength|prefix\(|characterLimit' CornerPet/Capture/CaptureTextEditor.swift; then exit 1; fi
```

Expected: bridge tests pass and the scan has no match. Do not commit.

---

### Task 7.4: Build the fixed SwiftUI capture shell and placeholders

**Files:**

- Create: `CornerPet/Capture/CaptureHeaderView.swift`
- Create: `CornerPet/Capture/ItemRow.swift`
- Create: `CornerPet/Capture/InboxView.swift`
- Create: `CornerPet/Capture/CaptureNavigationBar.swift`
- Create: `CornerPet/Capture/CapturePanelView.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Task 6 capture state/commands and Task 7 shell/inbox/text-editor state.
- Produces: a complete capture-first view with stable accessibility identifiers.

- [ ] **Step 1: Add compile-time view construction RED coverage**

In `CaptureLayoutTests`, instantiate `CapturePanelView` with in-memory stores and no-op pin/command closures. Add assertions against pure destination/copy metrics; SwiftUI view-tree introspection is not introduced because third-party inspection libraries are forbidden.

- [ ] **Step 2: Add all view references and run RED**

Run `build-for-testing`. Expected: missing view types until implemented.

- [ ] **Step 3: Implement fixed shell composition**

Use one root `VStack(spacing: 8)` constrained to `CaptureLayout.panelSize`, with this order:

```swift
CaptureHeaderView(...).frame(height: CaptureLayout.headerHeight)
CaptureTextEditor(...).frame(height: measuredInputHeight)
if let error = captureViewModel.saveError { CaptureSaveErrorBanner(...) }
destinationContent.frame(maxWidth: .infinity, maxHeight: .infinity)
CaptureNavigationBar(...).frame(height: CaptureLayout.navigationHeight)
```

Apply outer padding 12, a rounded material background, and clipping only at the outer shell. Do not put the entire `VStack` in a `ScrollView`.

Required copy and identifiers:

| Element | Copy | Identifier |
|---|---|---|
| Root | none | `capture.panel` |
| Header | `CornerPet` + `角落灵感箱` | `capture.header` |
| Input prompt | `记下想法… / Capture a thought…` | `capture.input` |
| Retry | `重试 / Retry` | `capture.error.retry` |
| Error dismiss | `关闭 / Dismiss` | `capture.error.dismiss` |
| Inbox list | none | `inbox.list` |
| Empty list | `还没有想法 / No ideas yet` | `inbox.empty` |
| Nav items | exact bilingual destination titles | `nav.<rawValue>` |
| Placeholders | destination bilingual title | `placeholder.<rawValue>` |

`InboxView` alone owns a `ScrollView`/`LazyVStack`. `ItemRow` shows the unchecked circle, full text, and created time. Completion/favorite/delete controls may be drawn as noninteractive visual affordances but must have `allowsHitTesting(false)` and must not claim success; Task 8 makes them interactive.

Non-inbox destinations render a centered icon and bilingual title in the middle region. They do not load or mutate data.

The header pin control is disabled when `pinAvailable == false`, has help text `置顶功能将在窗口阶段启用 / Pinning becomes available in the window stage`, and never toggles local fake state. This keeps the visible contract honest until Task 9.

- [ ] **Step 4: Adapt one-shot commands inside the view**

Maintain a local `@State private var focusRequest = 0`. When `pendingPanelCommand` changes, consume exactly once:

- `.focusInputAtEnd`: increment `focusRequest`.
- `.close(reason)`: pass it to `onPanelCommand`.

On appear, call `captureViewModel.restoreDraft()` and `inboxViewModel.load()`. Connect `captureViewModel.onItemCreated = { [weak inboxViewModel] in inboxViewModel?.prepend($0) }` in the composition root, not during repeated SwiftUI body evaluation.

- [ ] **Step 5: Build and run direct XCTest to GREEN**

Expected: the product/test bundle compiles, all unit tests pass, and no business method for placeholder destinations exists.

- [ ] **Step 6: Scope scan and checkpoint**

Run:

```bash
if rg -n 'archiveItem|favoriteItem|deleteItem|searchItems|updateItem' CornerPet/Capture; then exit 1; fi
git diff --check
```

Expected: no business-operation matches and no whitespace errors. Do not commit.

---

### Task 7.5: Host the capture shell in the existing AppKit panel

**Files:**

- Create: `CornerPet/Capture/CaptureCompositionRoot.swift`
- Modify: `CornerPet/Panel/CapturePanelController.swift`
- Modify: `CornerPet/App/AppDelegate.swift`
- Modify: `CornerPetTests/PanelAnimatorTests.swift`
- Create: `CornerPetTests/CaptureCompositionTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: production container/stores, existing panel lifecycle, Task 7 root view.
- Produces: visible usable capture UI without changing hot-corner geometry or animation.

- [ ] **Step 1: Write hosting/lifecycle RED tests**

Add:

```swift
func testControllerHostsSuppliedContentInsideTrackedProbe()
func testHostedContentDoesNotRemoveRequiredTrackingArea()
func testDidOpenRestoresDraftAndRequestsInputFocus()
func testEscapeCloseReasonUsesCoordinatorEscapeBeforeDismiss()
func testSubmittedOutsideCloseReasonDismissesWithoutEscapeSuppression()
func testTerminationFlushesDraftBeforeCoordinatorStops()
func testCompositionConnectsCreatedItemToInboxExactlyOnce()
```

The controller test supplies an `NSView` with a known accessibility identifier and asserts it is a descendant of `panel.contentView`, while the outer content view still owns `.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`, and not `.mouseMoved`.

- [ ] **Step 2: Run direct XCTest and verify behavioral RED**

Expected: tests fail because the controller has no hosted-content seam and the app has no composition root.

- [ ] **Step 3: Extend `CapturePanelController` without replacing the probe**

Add:

```swift
typealias HostedContentFactory = @MainActor () -> NSView

func installHostedContentFactory(_ factory: @escaping HostedContentFactory)
func handleCaptureCommand(_ command: CapturePanelCommand)
```

`EscapeInputProbe` remains the panel's outer `contentView` and tracking owner. Give it one hosted child pinned to all four edges with Auto Layout. On `.close(.escape)`, call the same `handleEscape()` path that invokes `onEscape` before `dismiss()`. On `.close(.submittedOutside)`, call only `dismiss()`. `.focusInputAtEnd` is consumed in SwiftUI and is inert at controller level.

Do not call `NSApp.activate()` and do not change `CornerPanel` level/collection behavior.

- [ ] **Step 4: Implement `CaptureCompositionRoot`**

Create one shared `ModelContext(container)`, `DraftStore`, and `ItemStore`. Create the view models once. Use weak panel capture for `pointerInsidePanel`:

```swift
pointerInsidePanel: { [weak panelController] in
    guard let frame = panelController?.keepOpenFrame else { return false }
    return frame.contains(NSEvent.mouseLocation)
},
isPinned: { false }
```

Pin remains unavailable and false until Task 9. Connect `captureViewModel.onItemCreated` to `inboxViewModel.prepend`. `applicationWillTerminate()` calls `captureViewModel.flushDraft()`.

- [ ] **Step 5: Refactor `AppDelegate` production composition while retaining injectable tests**

Default launch order:

1. Build the existing `CapturePanelController` with main-screen lookup and `.topLeft`.
2. Create `ModelContainerFactory.makeProduction()` and `CaptureCompositionRoot`.
3. Install an `NSHostingView(rootView: composition.makeRootView())` through the controller factory seam.
4. Create/connect/start `CornerTriggerCoordinator` exactly as today.
5. On panel `.didOpen`, call `captureViewModel.panelDidOpen()` in addition to the existing coordinator lifecycle callback.
6. On termination, flush composition draft first, then stop the trigger coordinator.

If production container creation throws, keep the trigger/panel process alive with a non-persisting diagnostic capture error view and log the error through `NSLog`; do not silently substitute an in-memory store and claim persistence.

Update the injectable AppDelegate initializer to accept a composition factory only where tests need it; retain existing panel/coordinator factory coverage.

- [ ] **Step 6: Run direct XCTest and Debug build to GREEN**

Run the authoritative direct workflow and the arm64 Debug build. Expected: all previous panel/trigger tests plus hosting/composition tests pass, `BUILD SUCCEEDED`, and geometry/timing tests remain unchanged.

- [ ] **Step 7: Checkpoint; do not commit**

Inspect only the AppDelegate/controller/composition diffs. Confirm no focus activation call, no mouse monitor, no replacement of tracking panels, and no signing changes. Do not commit.

---

### Task 7.6: Add a deterministic UI-test launch path and capture flow

**Files:**

- Create: `CornerPetUITests/CaptureFlowUITests.swift`
- Modify: `CornerPet/App/AppDelegate.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: launch arguments used only by automated UI verification.
- Produces: a directly opened, memory-only capture panel in UI tests without weakening production startup.

- [ ] **Step 1: Write UI flow tests**

Use launch arguments `--cornerpet-ui-testing`, `--cornerpet-open-capture`, and `--cornerpet-memory-store`. Add:

```swift
func testCaptureReturnAddsNewestItemAndKeepsFixedShellVisible()
func testShiftReturnKeepsMultilineDraftThenReturnSubmits()
func testEscapeClosesAndReopenRestoresDraft()
func testBottomNavigationShowsOnlyPlaceholderStateForDeferredDestinations()
```

The first flow:

```swift
let input = app.textViews["capture.input"]
XCTAssertTrue(input.waitForExistence(timeout: 5))
input.click()
input.typeText("first idea")
input.typeKey(.return, modifierFlags: [])
XCTAssertTrue(app.staticTexts["first idea"].waitForExistence(timeout: 2))
XCTAssertTrue(app.otherElements["capture.header"].exists)
XCTAssertTrue(app.otherElements["inbox.list"].exists)
XCTAssertTrue(app.buttons["nav.inbox"].exists)
```

Navigation flow clicks Favorites, Archive, Settings, and Inbox; it asserts the matching placeholder identifier and proves no archive/favorite/settings content controls exist.

- [ ] **Step 2: Add UI-test membership and verify build RED**

Run `build-for-testing`. Expected: either UI test compilation fails due to missing launch path or tests build but cannot find the capture input when executed.

- [ ] **Step 3: Implement test-only launch composition**

When `--cornerpet-ui-testing` is present:

- `--cornerpet-memory-store` selects `ModelContainerFactory.makeInMemory()` instead of production storage.
- `--cornerpet-open-capture` presents on the main screen after composition/trigger wiring completes.
- no production default changes; absent flags preserve invisible hot-corner startup.

Do not expose these flags in settings or normal UI.

- [ ] **Step 4: Build all tests and run direct unit XCTest**

Run the authoritative direct workflow. Expected: all unit tests pass and `CaptureFlowUITests.swift` compiles into `CornerPetUITests.xctest`.

- [ ] **Step 5: Attempt the UI suite with the known runner caveat**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData \
  -only-testing:CornerPetUITests/CaptureFlowUITests test
```

Expected success case: all four UI flows pass. Known environment case: worker materialization stalls before UI execution; record the exact stage and do not claim the UI suite passed. In that case, compilation plus the manual acceptance matrix in Task 7.7 are mandatory.

- [ ] **Step 6: Checkpoint; do not commit**

Confirm test launch arguments are gated and no real user store is touched. Do not commit.

---

### Task 7.7: Visual/manual acceptance and complete Task 7 gate

**Files:** inspect only unless acceptance identifies a concrete defect.

**Interfaces:** produces the accepted usable capture-first panel and handoff to Task 8.

- [ ] **Step 1: Run the authoritative unit workflow exactly**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected: every prior and Task 7 unit/integration test passes.

- [ ] **Step 2: Run Debug arm64 build and forbidden-API scans**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData build

if rg -n 'URLSession|CloudKit|addGlobalMonitorForEvents|addLocalMonitorForEvents|\.mouseMoved' \
  CornerPet/Capture CornerPet/Persistence; then exit 1; fi
```

Expected: `BUILD SUCCEEDED` and no forbidden match.

- [ ] **Step 3: Perform the 360×450 visual matrix**

On the main display, verify and capture evidence for:

1. panel left edge equals screen left edge; panel top equals menu bar lower edge; size is 360×450;
2. header stays fixed while scrolling at least 20 inbox rows;
3. navigation stays fixed during the same scroll;
4. one line starts at 30 pt; lines 2–5 grow; line 6 keeps 110 pt and enables internal input scrolling;
5. inbox remains independently scrollable after the input reaches five lines;
6. newest successful item appears at the first row without reopening when pointer is inside;
7. pointer outside/unpinned success closes; Escape preserves and restores draft at insertion end;
8. error banner sits below input and does not block typing;
9. Favorites/Archive/Settings show only bilingual placeholders;
10. full-screen Safari/Xcode invocation does not switch Space and the panel remains above the app.

Expected: all ten conditions pass. A visual or behavior defect returns to Luna with the smallest reproducible test or explicit manual reproduction.

- [ ] **Step 4: Terra high performs final Task 7 review**

Terra must review:

- fixed-versus-scroll layout ownership;
- `NSTextView` IME, selection, Return, Shift-Return, Escape, and focus-at-end behavior;
- Task 5/6 integration and failure text preservation;
- single composition root and no SwiftData access in SwiftUI views;
- truthful disabled pin affordance and placeholder-only deferred destinations;
- explicit PBX membership and preservation of signing/dirty worktree;
- direct XCTest, Debug build, UI-runner status, and manual matrix evidence.

Expected: no P0/P1 defect and no unacknowledged UI-runner gap.

- [ ] **Step 5: Record checkpoint; do not commit**

Run `git status --short`, report every Task 7 file plus validation results, and wait for Jack. Do not commit, push, or create a PR.

## Plan Self-Review

- **Specification coverage:** fixed header/input/navigation, 1–5-line growth, internal input scroll, independent newest-first inbox, errors, auto-focus, Return/Shift-Return/Escape, and navigation placeholders all map to implementation and verification steps.
- **Deferred scope:** Favorites/Archive/Settings business, archive/favorite/delete/edit/search/undo, pin window behavior, and settings remain outside Task 7.
- **Type consistency:** Task 5 store and snapshot names and Task 6 view-model/policy/close-reason names are reused exactly.
- **PBX strategy:** every new product/unit/UI-test file is manually referenced and assigned target membership; regeneration and signing edits are forbidden.
- **Direct testing:** the exact known direct XCTest workflow is authoritative. Full scheme/UI execution is attempted and reported honestly under the known worker-materialization limitation.
- **Visual gate:** 360×450 placement, fixed/scroll regions, multiline behavior, placeholders, errors, and full-screen integration require manual evidence before acceptance.
- **Checkpoint policy:** all stage boundaries explicitly wait for Jack and create no Git commit.

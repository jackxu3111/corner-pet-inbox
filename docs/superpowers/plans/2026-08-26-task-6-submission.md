# Task 6 Conditional Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Luna max implements one red/green slice at a time; Terra high must accept the Task 6 gate before Task 7 UI work begins.

**Goal:** Implement a testable `CaptureViewModel` that restores and stages draft text, maps Return/Shift-Return/Escape, preserves text on every failure, and decides whether a successful submission refocuses or closes based on pointer and pin state.

**Architecture:** `CaptureViewModel` is a main-actor observable state owner that depends only on the Task 5 store protocols and injected clock/panel-state providers. Pure keyboard and post-submit policies make modifier and pointer/pin branches deterministic; the view model emits one-shot commands that the Task 7 AppKit/SwiftUI adapter will consume.

**Tech Stack:** Swift 6, Foundation, Observation, SwiftData through Task 5 protocols, XCTest; no Task 7 view and no third-party dependency

**Spec:** `docs/superpowers/specs/2026-08-25-hot-corner-capture-interaction-design.md`

## Global Constraints

- Execute only after Task 5 passes Terra high review; consume its exact `DraftStoring`, `ItemStoring`, `DraftSnapshot`, and `IdeaItemSnapshot` contracts.
- Work in `/Users/jack/MyApp/CornerPet`; preserve the dirty worktree and all Task 1–5 changes.
- Do not commit, push, create a PR, discard, regenerate, or blanket-revert files. Every commit boundary is a checkpoint that waits for Jack's explicit authorization.
- macOS 14+, Apple Silicon arm64, Swift 6, AppKit + SwiftUI + SwiftData, local-only, and no third-party dependency remain fixed.
- Preserve the 0.400-second trigger, `86×20 + 20×86 pt` top-left trigger arms, 0.100-second keep-open close debounce, and the 360×450 pt panel flush with the screen left edge and menu bar lower edge.
- Return trims only leading/trailing whitespace and submits one item; Shift-Return inserts a newline; Escape preserves a draft and requests close only after the draft flush succeeds.
- A normalized empty Return creates no formal item and keeps focus in the input.
- Item-save failure retains exact draft text, leaves the panel open, and exposes a retryable persistent error. Explicit error dismissal never clears text.
- A successful item save clears the draft before any close/refocus command is emitted. Duplicate formal items remain permitted.
- Pointer inside keeps and refocuses; pointer outside and unpinned closes; pinned keeps and refocuses regardless of pointer.
- Task 6 does not add the complete panel UI, an `NSHostingView`, inbox rows, navigation, archive/favorites/settings pages, pin movement/resizing, or item lifecycle actions.
- Use the one-command Xcode beta `DEVELOPER_DIR` override; never change global `xcode-select`.
- Continue the explicit PBX file-reference/source-membership strategy; do not regenerate the project or alter signing.

---

## Task 5 Entry Gate

Before editing, run the exact direct unit workflow:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected: Task 5 and all prior tests pass. If they do not, stop Task 6 and return the defect to the Task 5 implementation slice.

## File Responsibility Map

| File | Responsibility |
|---|---|
| `CornerPet/Capture/CaptureViewModel.swift` | Observable draft, submission, retry, error, one-shot command, and created-item event state |
| `CornerPet/Capture/CaptureKeyboardPolicy.swift` | Pure Return/Shift-Return/Escape mapping without AppKit |
| `CornerPet/Capture/PostSubmissionPolicy.swift` | Pure pointer/pin truth table |
| `CornerPetTests/CaptureKeyboardPolicyTests.swift` | Keyboard mapping and no-delete shortcut contract |
| `CornerPetTests/PostSubmissionPolicyTests.swift` | All pointer/pin decision branches |
| `CornerPetTests/CaptureViewModelTests.swift` | Restore, draft staging, empty input, Escape, failures, retry, and command consumption |
| `CornerPetTests/CaptureSubmissionIntegrationTests.swift` | Real in-memory Task 5 stores plus view-model success flow |
| `CornerPet.xcodeproj/project.pbxproj` | Explicit Capture group and product/test memberships only |

## Stable Interfaces Produced for Task 7

```swift
import Foundation
import Observation

enum CaptureKeyboardAction: Equatable {
    case submit
    case insertNewline
    case escape
    case passThrough
}

struct CaptureKeyboardPolicy {
    static func action(
        keyCode: UInt16,
        isShiftPressed: Bool
    ) -> CaptureKeyboardAction
}

enum PostSubmissionDecision: Equatable {
    case keepOpenAndRefocus
    case closePanel
}

struct PostSubmissionPolicy {
    static func decide(pointerInside: Bool, isPinned: Bool) -> PostSubmissionDecision
}

enum CaptureCloseReason: Equatable {
    case escape
    case submittedOutside
}

enum CapturePanelCommand: Equatable {
    case focusInputAtEnd
    case close(CaptureCloseReason)
}

enum CaptureSaveError: Equatable {
    case saveFailed

    var englishMessage: String { "Save failed. Try again." }
    var chineseMessage: String { "保存失败，请重试。" }
}

@MainActor
@Observable
final class CaptureViewModel {
    private(set) var draftText: String
    private(set) var saveError: CaptureSaveError?
    private(set) var isSubmitting: Bool
    private(set) var pendingPanelCommand: CapturePanelCommand?

    var onItemCreated: ((IdeaItemSnapshot) -> Void)?

    init(
        draftStore: any DraftStoring,
        itemStore: any ItemStoring,
        now: @escaping @MainActor () -> Date = { .now },
        pointerInsidePanel: @escaping @MainActor () -> Bool,
        isPinned: @escaping @MainActor () -> Bool
    )

    func restoreDraft()
    func panelDidOpen()
    func draftDidChange(_ text: String)
    func handleReturn(isShiftPressed: Bool) -> CaptureKeyboardAction
    func handleEscape()
    func retryLastFailedOperation()
    func dismissSaveError()
    func flushDraft()
    func consumePanelCommand() -> CapturePanelCommand?
}
```

Task 7 owns actual newline insertion in its `NSTextView` adapter when `handleReturn(isShiftPressed: true)` returns `.insertNewline`. Task 6 must not mutate the string for Shift-Return because only the text control knows the current selection and marked-text state.

State invariants:

1. `draftText` is the user-visible source of truth and is never derived from the item list.
2. `isSubmitting` prevents repeated Return/retry calls from overlapping.
3. `onItemCreated` fires exactly once after item save and draft clear both succeed.
4. `pendingPanelCommand` is one-shot; `consumePanelCommand()` returns then clears it.
5. `saveError` stays visible through unrelated typing and disappears only on retry start, successful save, or explicit dismissal.
6. A draft restore failure produces `.saveFailed`, an empty visible draft only when no prior visible text exists, and no close command.

---

### Task 6.1: Implement pure keyboard mapping

**Files:**

- Create: `CornerPet/Capture/CaptureKeyboardPolicy.swift`
- Create: `CornerPetTests/CaptureKeyboardPolicyTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: macOS virtual key codes only; Return is 36 and keypad Enter is 76, Escape is 53.
- Produces: `CaptureKeyboardAction` and `CaptureKeyboardPolicy.action(keyCode:isShiftPressed:)`.

- [ ] **Step 1: Preserve the baseline and add explicit Capture references**

Run `git status --short` and inspect the PBX Capture/test insertion points. Add one `Capture` product group, the policy/test file references, build files, and source memberships with unique IDs.

- [ ] **Step 2: Write keyboard-policy red tests**

```swift
import XCTest

@testable import CornerPet

final class CaptureKeyboardPolicyTests: XCTestCase {
    func testReturnAndKeypadEnterSubmitWithoutShift() {
        XCTAssertEqual(CaptureKeyboardPolicy.action(keyCode: 36, isShiftPressed: false), .submit)
        XCTAssertEqual(CaptureKeyboardPolicy.action(keyCode: 76, isShiftPressed: false), .submit)
    }

    func testShiftReturnAndShiftKeypadEnterInsertNewline() {
        XCTAssertEqual(CaptureKeyboardPolicy.action(keyCode: 36, isShiftPressed: true), .insertNewline)
        XCTAssertEqual(CaptureKeyboardPolicy.action(keyCode: 76, isShiftPressed: true), .insertNewline)
    }

    func testEscapeMapsToEscapeAndOtherKeysPassThrough() {
        XCTAssertEqual(CaptureKeyboardPolicy.action(keyCode: 53, isShiftPressed: false), .escape)
        XCTAssertEqual(CaptureKeyboardPolicy.action(keyCode: 51, isShiftPressed: false), .passThrough)
    }
}
```

- [ ] **Step 3: Run `build-for-testing` and verify RED**

Expected: compile fails because the policy types do not exist; PBX parsing must succeed.

- [ ] **Step 4: Implement the pure switch**

```swift
struct CaptureKeyboardPolicy {
    static func action(keyCode: UInt16, isShiftPressed: Bool) -> CaptureKeyboardAction {
        switch keyCode {
        case 36, 76:
            return isShiftPressed ? .insertNewline : .submit
        case 53:
            return .escape
        default:
            return .passThrough
        }
    }
}
```

Do not import AppKit and do not map Delete, Command-Delete, or a draft-clear shortcut.

- [ ] **Step 5: Run build plus direct XCTest to GREEN, then checkpoint**

Run the exact two-command entry-gate workflow. Expected: all prior tests plus three policy tests pass. Run `git diff --check`; do not commit.

---

### Task 6.2: Implement the pure pointer/pin decision

**Files:**

- Create: `CornerPet/Capture/PostSubmissionPolicy.swift`
- Create: `CornerPetTests/PostSubmissionPolicyTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: deadline-time `pointerInside` and current `isPinned` booleans.
- Produces: `PostSubmissionPolicy.decide(pointerInside:isPinned:)`.

- [ ] **Step 1: Write the complete truth-table RED test**

```swift
final class PostSubmissionPolicyTests: XCTestCase {
    func testEveryPointerAndPinBranch() {
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: true, isPinned: false),
            .keepOpenAndRefocus
        )
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: false, isPinned: false),
            .closePanel
        )
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: true, isPinned: true),
            .keepOpenAndRefocus
        )
        XCTAssertEqual(
            PostSubmissionPolicy.decide(pointerInside: false, isPinned: true),
            .keepOpenAndRefocus
        )
    }
}
```

- [ ] **Step 2: Add memberships and run RED**

Run `build-for-testing`. Expected: missing policy types, not a PBX error.

- [ ] **Step 3: Implement the minimal rule**

```swift
static func decide(pointerInside: Bool, isPinned: Bool) -> PostSubmissionDecision {
    isPinned || pointerInside ? .keepOpenAndRefocus : .closePanel
}
```

- [ ] **Step 4: Run direct XCTest to GREEN and checkpoint**

Expected: all tests pass, including all four truth-table branches. Do not add actual pin state or window movement. Do not commit.

---

### Task 6.3: Build draft restore, staging, focus, and Escape preservation

**Files:**

- Create: `CornerPet/Capture/CaptureViewModel.swift`
- Create: `CornerPetTests/CaptureViewModelTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Task 5 stores, injected date/pointer/pin providers.
- Produces: the `CaptureViewModel` interface above except submission/retry behavior completed in Task 6.4.

- [ ] **Step 1: Create strict test doubles and RED tests**

The draft double records staged values, flush count, clear count, and configurable restore/flush errors. The item double records calls and initially returns no item. Add:

```swift
func testRestoreLoadsDraftAndPanelOpenRequestsFocusAtEnd()
func testDraftChangeStagesExactUntrimmedTextAndDate()
func testShiftReturnReturnsInsertNewlineWithoutSubmittingOrChangingText()
func testEscapeFlushesThenRequestsCloseWithoutClearingDraft()
func testEscapeFlushFailureKeepsPanelOpenAndShowsPersistentError()
func testConsumePanelCommandClearsTheOneShotCommand()
func testDraftWriteCallbackShowsErrorWithoutClearingVisibleText()
```

Critical Escape assertion:

```swift
viewModel.draftDidChange("unfinished\nthought")
viewModel.handleEscape()

XCTAssertEqual(draftStore.flushedCount, 1)
XCTAssertEqual(draftStore.clearedCount, 0)
XCTAssertEqual(viewModel.draftText, "unfinished\nthought")
XCTAssertEqual(viewModel.consumePanelCommand(), .close(.escape))
```

- [ ] **Step 2: Add memberships and verify RED**

Run `build-for-testing`. Expected: `CaptureViewModel` is undefined.

- [ ] **Step 3: Implement restore/stage/focus/Escape state**

Implement the stable constructor and these rules:

- Constructor installs `draftStore.onWriteFailure = { [weak self] _ in self?.saveError = .saveFailed }` on the main actor.
- `restoreDraft()` sets `draftText` from `restore()`; failure leaves any existing visible text intact and sets the persistent error.
- `panelDidOpen()` replaces any stale command with `.focusInputAtEnd`.
- `draftDidChange` updates visible text immediately, then calls `stage` with the injected date.
- Shift-Return returns `.insertNewline` with no store or item call.
- Escape calls `flush`; on success emits `.close(.escape)`, on failure emits no command and sets the error.
- `consumePanelCommand` atomically reads and clears the command.

Do not call `CapturePanelController` directly; Task 7 owns command adaptation.

- [ ] **Step 4: Run direct XCTest to GREEN and checkpoint**

Expected: all seven view-model tests pass and old panel tests remain unchanged. Run `git diff --check`; do not commit.

---

### Task 6.4: Implement Return, error retention, and retry

**Files:**

- Modify: `CornerPet/Capture/CaptureViewModel.swift`
- Modify: `CornerPetTests/CaptureViewModelTests.swift`

**Interfaces:**

- Consumes: `ItemStoring.createInboxItem`, `DraftStoring.clear`, `PostSubmissionPolicy`.
- Produces: complete Return/retry behavior and exactly-once `onItemCreated` events.

- [ ] **Step 1: Add submission RED tests**

```swift
func testEmptyNormalizedReturnCreatesNothingAndRefocuses()
func testSuccessfulReturnClearsOnlyAfterItemStoreSuccess()
func testItemSaveFailureKeepsExactDraftAndPanelOpen()
func testRetryAfterFailureCreatesOnceThenClearsAndDismissesError()
func testDismissErrorKeepsDraftAndAllowsLaterRetry()
func testRepeatedReturnWhileSubmittingIsIgnored()
func testCreatedItemCallbackFiresOnceAfterClearSucceeds()
```

The failure-order double must record operations:

```swift
XCTAssertEqual(operationLog, ["item.create"])
XCTAssertEqual(draftStore.clearedCount, 0)
XCTAssertEqual(viewModel.draftText, "  keep me  ")
XCTAssertEqual(viewModel.saveError, .saveFailed)
XCTAssertNil(viewModel.consumePanelCommand())
```

The success test must prove the store receives normalized text while visible failure text remains unmodified until success:

```swift
viewModel.draftDidChange("  idea\n  ")
XCTAssertEqual(viewModel.handleReturn(isShiftPressed: false), .submit)
XCTAssertEqual(itemStore.receivedTexts, ["idea"])
XCTAssertEqual(operationLog, ["item.create", "draft.clear"])
XCTAssertEqual(viewModel.draftText, "")
```

- [ ] **Step 2: Run direct XCTest and verify behavioral RED**

The test bundle should compile, then fail the new Return/retry assertions because submission is not implemented.

- [ ] **Step 3: Implement submission with explicit ordering**

Use a private `submitCurrentDraft()`:

```swift
private func submitCurrentDraft() {
    guard !isSubmitting else { return }
    let normalized = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        pendingPanelCommand = .focusInputAtEnd
        return
    }

    isSubmitting = true
    defer { isSubmitting = false }
    do {
        guard let item = try itemStore.createInboxItem(text: normalized, at: now()) else {
            pendingPanelCommand = .focusInputAtEnd
            return
        }
        try draftStore.clear(updatedAt: now())
        draftText = ""
        saveError = nil
        onItemCreated?(item)
        pendingPanelCommand = switch PostSubmissionPolicy.decide(
            pointerInside: pointerInsidePanel(),
            isPinned: isPinned()
        ) {
        case .keepOpenAndRefocus: .focusInputAtEnd
        case .closePanel: .close(.submittedOutside)
        }
    } catch {
        saveError = .saveFailed
        pendingPanelCommand = nil
    }
}
```

`handleReturn(isShiftPressed:)` first asks `CaptureKeyboardPolicy` for key code 36; `.insertNewline` returns immediately, `.submit` calls the private method, then returns `.submit`. `retryLastFailedOperation()` clears only the displayed error at retry start and dispatches the recorded failure intent, so restore, ordinary/debounced flush, Escape flush, item creation, draft clear, and replacement-draft persistence each retry only their own operation. Only a submission chain originally initiated by Return/Keypad Enter may call `ItemStore`. `dismissSaveError` sets only `saveError = nil` and keeps the retry intent.

If `ItemStore` succeeds but `DraftStore.clear` throws, retain visible draft text, show the error, and emit no item callback or panel command. Cache an immutable pending-submission context containing the first successful item snapshot plus the submitted draft text/revision, block any second create while it exists, and keep its recovery intent dominant over later draft-write or Escape failures. Retry clears the submitted draft without recreating the item. A subsequent Return while recovery is pending resumes that same clear/replacement-flush operation, including after explicit error dismissal, and never creates another item. If the user edited after the failed clear, persist that replacement draft before firing the original item callback and post-submit command exactly once.

- [ ] **Step 4: Run direct XCTest to GREEN**

Run the exact direct workflow. Expected: all prior tests and the seven new submission tests pass.

- [ ] **Step 5: Checkpoint; do not commit**

Confirm no UI type, AppKit controller call, archive/favorite operation, or text-length limit entered `CaptureViewModel`. Do not commit.

---

### Task 6.5: Integrate the view model with real in-memory stores

**Files:**

- Create: `CornerPetTests/CaptureSubmissionIntegrationTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: Task 5 real `DraftStore`/`ItemStore` and Task 6 `CaptureViewModel`.
- Produces: evidence that protocol-test behavior matches SwiftData behavior.

- [ ] **Step 1: Write real-store integration RED tests**

```swift
@MainActor
final class CaptureSubmissionIntegrationTests: XCTestCase {
    func testRealStoresPersistItemClearDraftAndKeepOpenWhenPointerInside() throws
    func testRealStoresCloseWhenPointerOutsideAndUnpinned() throws
    func testRealStoresKeepOpenWhenPinnedAndPointerOutside() throws
    func testEscapeFlushSurvivesContainerRecreationWithoutFormalItem() throws
}
```

For each test, create one in-memory container and one shared `ModelContext`, construct `DraftStore(context:scheduler:debounce:)` and `ItemStore(context:)`, and pass them to the view model. For Escape restart evidence, use an explicit temporary store URL, release the first container/store scope, recreate with the same URL, and assert the draft is restored while `fetchInbox()` is empty.

- [ ] **Step 2: Add the test target membership and run RED if integration exposes a mismatch**

Expected: tests either expose a store/view-model mismatch or pass immediately. If they pass immediately, retain them as integration evidence and do not manufacture a failure.

- [ ] **Step 3: Apply only a minimal root-cause fix when a mismatch exists**

Any fix must begin with the failing assertion and remain inside Task 5 store integration or Task 6 view-model ordering. Do not change hot-corner timing, panel geometry, or introduce UI.

- [ ] **Step 4: Run direct XCTest and Debug build**

Run the exact direct workflow, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData build
```

Expected: all tests pass and Debug reports `BUILD SUCCEEDED`.

---

### Task 6.6: Task 6 stage gate

**Files:** inspect only unless a gate finds a concrete defect.

**Interfaces:** produces the accepted state/command contract Task 7 may render.

- [ ] **Step 1: Run the authoritative direct workflow exactly**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected: all prior, persistence, policy, view-model, and integration tests pass.

- [ ] **Step 2: Attempt the supplementary full scheme**

Use the Task 5 full-scheme command. Success is `TEST SUCCEEDED`; if worker materialization stalls again, record the limitation and rely on direct XCTest plus Debug build for the unit gate.

- [ ] **Step 3: Terra high performs behavioral review**

Terra must verify:

- Return trims only edges, rejects empty, and does not block duplicates;
- item persistence occurs before draft clear and failures preserve exact text;
- Shift-Return is delegated as newline insertion and never submits;
- Escape flushes and closes on success, but stays open on flush failure;
- retry/error dismissal rules match the specification;
- all four pointer/pin combinations are covered;
- item callback and panel command fire only after full success;
- there is no complete capture UI or Task 7/8/9 behavior.

Expected: no P0/P1 issue. Each issue returns to Luna with a focused failing test.

- [ ] **Step 4: Checkpoint; do not commit**

Run `git status --short`, report Task 6 files and test evidence, and wait for Jack. Do not commit, push, or create a PR.

## Plan Self-Review

- **Specification coverage:** restore/focus, Return, Shift-Return, Escape, failure retention, retry, error dismissal, pointer/pin decisions, and real-store integration are each explicit.
- **Boundary coverage:** view model emits commands but does not own AppKit window behavior or SwiftUI layout.
- **Type consistency:** every Task 7 dependency is declared in the stable interface section and consumes Task 5 names unchanged.
- **Project integration:** all Capture and test files use explicit PBX entries without regenerating the project.
- **Verification realism:** direct XCTest is the required unit gate; full scheme remains supplementary under the known worker-materialization limit.
- **Checkpoint policy:** no Git commit occurs without Jack's explicit authorization.

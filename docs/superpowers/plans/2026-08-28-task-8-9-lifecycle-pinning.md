# Task 8–9 Item Lifecycle and Panel Pinning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` for every slice and `superpowers:verification-before-completion` before reporting either Task complete. Execute Task 8 before Task 9. Steps use checkbox (`- [ ]`) syntax for tracking. Luna implements one thin vertical slice at a time; Terra reviews each slice before the next starts.

**Goal:** Complete formal-item lifecycle (archive undo, Favorites, search, inline edit, confirmed permanent deletion) and then install one deterministic panel lifecycle owner for 120 ms auto-hide, errors, external focus, pinning, movement, resizing, size persistence, and unpin return.

**Architecture:** Extend the existing `ItemStore` and Task 7 inbox/archive UI instead of rebuilding the already-working archive foundation. A shared item-edit module and narrow lifecycle store interface keep persistence rules out of SwiftUI. Task 9 introduces a pure `PanelStateMachine` plus one scheduling adapter; the prototype trigger reducer stops owning close deadlines, so only one 120 ms auto-hide token can exist.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`, `NSTextView`, `NSWindowDelegate`), SwiftData, Observation, UserDefaults, XCTest, XCUITest; macOS 14+, arm64; no third-party dependencies

**Specs:**

- `docs/superpowers/specs/2026-08-25-hot-corner-capture-interaction-design.md`
- `docs/superpowers/specs/2026-08-26-atoll-style-corner-trigger-design.md` (prototype trigger behavior only)

## Global Constraints

- Work in `/Users/jack/MyApp/CornerPet` on `codex/cornerpet-task-4luna`; preserve the dirty Task 5–7 and trigger-rewrite work in place.
- Do not commit, push, create a PR, regenerate the Xcode project, change signing, delete `DerivedData`, or restore unrelated changes without Jack's explicit authorization.
- Task 8 must reuse the existing `archiveInboxItem`, `fetchArchive`, `InboxViewModel.complete`, `ArchiveViewModel`, `ArchiveView`, and archive navigation foundation. Extend or adapt them; do not build a second archive path.
- Task 8 scope is exactly archive undo, Favorites, Archive/Favorites search, inline edit, row-action locking, and confirmed permanent deletion. Task 9 scope is exactly panel lifecycle and pinning. No Task 10+ display/settings/reminder work and no visual redesign.
- Search is in-memory over loaded snapshots and must call `String.localizedStandardContains`; do not substitute lowercasing, regex, or SwiftData SQL-like matching.
- Archive undo is visible for exactly 5.000 seconds using an injected monotonic scheduler. Tests never sleep.
- Inline edit preserves `createdAt` and `movedAt`, changes `updatedAt` only after durable save, stores the exact edited text, and keeps the changed text/editor open on failure. The approved spec defines whitespace normalization only for new-item submission, so this plan does not invent edit trimming or empty-edit rejection.
- Permanent deletion is irreversible after explicit confirmation, has no second recycle bin, and keeps the item visible on save failure.
- Panel states are exactly `hidden`, `opening`, `openEmpty`, `draftLocked`, `itemEditing`, `pinned`, `error`, and `closing`. A pinned or error panel ignores pointer exit and external focus.
- The 120 ms Task 9 deadline is the only automatic-hide deadline. Deadline tokens use generations; cancellation alone is insufficient.
- Preserve 400 ms dwell, exact 86×20 + 20×86 pt top-left prototype trigger geometry, reversible 260/180 ms animation, 120 ms Reduce Motion behavior, full-screen auxiliary behavior, and the absence of mouse-moved monitors.
- Pinned size clamps to 280×320...480×640 pt and persists locally. Default remains 360×450 pt.
- Use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` per command; never change global `xcode-select`.
- Add surgical `PBXFileReference`, `PBXBuildFile`, group, and source-membership entries with unused IDs. Do not reorder existing PBX sections.

---

## Source-of-Truth Reconciliation

1. The full MVP interaction spec says an empty unpinned panel closes 120 ms after pointer exit. The later Atoll-style prototype spec temporarily put a 100 ms close policy in `HotCornerStateMachine` over the trigger-plus-panel union. Task 9 is the planned full lifecycle replacement, and the direct Task 9 requirement explicitly requires 120 ms and no competing timers. Therefore Task 9 removes the prototype `.closeDebounce` responsibility from `HotCornerStateMachine`/`CornerTriggerCoordinator` and moves it to `PanelStateMachine`.
2. Keep-open geometry remains the later approved trigger-plus-visible-panel union, preventing a close while the pointer crosses either owned trigger arm. Timing and eligibility come from the full lifecycle spec: only `openEmpty`, unpinned, non-error content may schedule the 120 ms close.
3. The original 2026-08-25 docs mention 6 pt trigger thickness and an 80 ms post-close debounce; the approved 2026-08-26 prototype and current code use 20 pt arms and suppress reopening until trigger exit. Task 8/9 do not alter geometry or add the 80 ms debounce. That conflict belongs to the trigger source, outside this plan.
4. The MVP plan proposed a new `Library/` folder, but Task 7 already created archive files under `CornerPet/Capture/`. To preserve user-owned dirty work and avoid duplicate modules, Task 8 continues in `CornerPet/Capture/`; it does not move existing files merely to match the older proposed tree.
5. Multiple simultaneous archive undo offers and empty inline edits are unspecified. This plan exposes only the latest archive offer (a new completion replaces the visible offer; the older item stays archived) and saves edit text exactly. Changing either rule requires a product-spec decision, not an implementation improvisation.

## Current Baseline and Gap Audit

Verified on 2026-08-28:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing

DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest \
  /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected entry result: `TEST BUILD SUCCEEDED`; direct XCTest executes 170 tests with 0 failures.

| Area | Already present and must be preserved | Missing for Task 8/9 |
|---|---|---|
| Persistence | `IdeaItem` has inbox/archive/favorite and timestamps; create/fetch inbox; archive fetch sorted by `movedAt`; inbox→archive durable mutation with rollback | Generic bucket fetch/move, favorite/unfavorite, archive undo, update text, permanent delete, failure rollback tests |
| Inbox/Archive | Inbox completes into Archive; failure keeps row; archive tab/view/load/retry exists | 5 s undo, Favorites tab, search, edit, delete confirmation, cross-list refresh |
| Capture | draft recovery, Return/Shift-Return/Escape, persistent save error, fixed shell | edit activity/error reporting to panel lifecycle; adaptive pinned size |
| Window | panel open/close animation, reversal, tracking frame, Escape, full-screen auxiliary | full content state machine, external-focus policy, pin shortcut/button, move/resize, size persistence, unpin return |
| Trigger | 400 ms dwell, 100 ms prototype keep-open close, stale-token rejection | close ownership must be removed to prevent competition with Task 9's 120 ms timer |
| Tests | 170 unit/integration tests pass; capture UI suite exists | item lifecycle, library flow, panel state, pin shortcut/adapter tests; XCUITest runner still has a known worker-materialization stall |

## File Responsibility Map

### Task 8

| File | Action and responsibility |
|---|---|
| `CornerPet/Persistence/ItemStore.swift` | Extend existing store with bucket query/move, text update, permanent delete; preserve rollback and existing wrappers |
| `CornerPet/Capture/ArchiveUndoController.swift` | Injected 5-second offer/token/expiry module; no persistence |
| `CornerPet/Capture/LibrarySearch.swift` | Pure `localizedStandardContains` filtering |
| `CornerPet/Capture/ItemEditViewModel.swift` | One active edit, original/working text, save/cancel/failure state |
| `CornerPet/Capture/InlineItemEditor.swift` | AppKit editor adapter for Return, Shift-Return, Escape, and focus-loss save |
| `CornerPet/Capture/FavoritesViewModel.swift` | Favorite list, search, unfavorite, edit/delete integration |
| `CornerPet/Capture/FavoritesView.swift` | Searchable flat Favorites UI |
| `CornerPet/Capture/InboxViewModel.swift` | Keep existing load/prepend/complete; add undo/favorite/delete callbacks |
| `CornerPet/Capture/ArchiveViewModel.swift` | Keep existing load/retry; add source/filtered items and edit/delete updates |
| `CornerPet/Capture/ItemRow.swift` | Inbox hover actions and inline editor; disable row actions while editing |
| `CornerPet/Capture/ArchiveItemRow.swift` | Archive editor and confirmed-delete affordance |
| `CornerPet/Capture/InboxView.swift`, `ArchiveView.swift`, `CapturePanelView.swift`, `CaptureCompositionRoot.swift` | Render/wire lifecycle modules and activity/error callbacks |
| `CornerPetTests/ItemLifecycleTests.swift` | Real in-memory store lifecycle and rollback tests |
| `CornerPetTests/ArchiveUndoControllerTests.swift` | Exact 5-second token tests |
| `CornerPetTests/LibraryViewModelTests.swift` | Favorites/Archive search and list-state tests |
| `CornerPetTests/ItemEditViewModelTests.swift` | Editing contract and timestamp/error tests |
| `CornerPetUITests/LibraryFlowUITests.swift` | User-visible archive/favorite/search/edit/delete flows |

### Task 9

| File | Action and responsibility |
|---|---|
| `CornerPet/Panel/PanelStateMachine.swift` | Pure eight-state reducer and generation-tagged effects |
| `CornerPet/Panel/PanelLifecycleCoordinator.swift` | The one 120 ms scheduler adapter; pointer deadline recheck; executes reducer effects |
| `CornerPet/Panel/PinnedPanelSizeStore.swift` | UserDefaults-backed clamped size only |
| `CornerPet/Panel/CornerPanel.swift` | Toggle movable/resizable configuration without changing full-screen behavior |
| `CornerPet/Panel/CapturePanelController.swift` | Adapt state effects to animation, focus, pin, return-to-corner, resize, external focus |
| `CornerPet/HotCorner/HotCornerStateMachine.swift` | Remove open-panel close deadline/effects; retain dwell and re-trigger lifecycle only |
| `CornerPet/HotCorner/CornerTriggerCoordinator.swift` | Remove panel close policy/auto-hide protection; publish trigger presence and presentation/retrigger only |
| `CornerPet/App/AppDelegate.swift` | Compose trigger, lifecycle coordinator, controller, and content activity |
| `CornerPet/Capture/CaptureCompositionRoot.swift`, `CaptureHeaderView.swift`, `CapturePanelView.swift` | Real pin state/action, content state, adaptive size |
| `CornerPetTests/PanelStateMachineTests.swift` | Exhaustive transition/deadline tests |
| `CornerPetTests/PanelLifecycleCoordinatorTests.swift` | Single-timer, stale-token, pointer/external-focus adapter tests |
| `CornerPetTests/PinnedPanelSizeStoreTests.swift` | clamp/default/persistence tests |
| `CornerPetTests/PanelAnimatorTests.swift`, `CornerTriggerCoordinatorTests.swift`, `CaptureCompositionTests.swift` | Migration and integration regressions |
| `CornerPetUITests/PinningFlowUITests.swift` | Pin button/shortcut and no-auto-hide observable flow |
| `CornerPet.xcodeproj/project.pbxproj` | Explicit memberships for all new product/test files only |

## Stable Interfaces to Implement

```swift
@MainActor
protocol ItemLifecycleStoring: ItemStoring {
    func fetchItems(in bucket: ItemBucket) throws -> [IdeaItemSnapshot]
    func moveItem(id: UUID, from: ItemBucket, to: ItemBucket, at: Date) throws -> IdeaItemSnapshot?
    func updateItemText(id: UUID, expectedBucket: ItemBucket, text: String, at: Date) throws -> IdeaItemSnapshot?
    func deletePermanently(id: UUID, expectedBucket: ItemBucket) throws -> Bool
}

struct ArchiveUndoOffer: Equatable {
    let generation: Int
    let item: IdeaItemSnapshot
    let expiresAt: TimeInterval
}

enum ItemEditSaveResult: Equatable { case saved(IdeaItemSnapshot), failed, missing }

enum PanelState: Equatable {
    case hidden, opening, openEmpty, draftLocked, itemEditing, pinned, error, closing
}

struct PanelContentStatus: Equatable {
    let hasDraft: Bool
    let hasItemEdit: Bool
    let hasError: Bool
}

struct PanelDeadline: Equatable {
    let generation: Int
    let dueAt: TimeInterval
}

enum PanelEvent: Equatable {
    case presentRequested
    case didOpen(content: PanelContentStatus, pointerInsideKeepOpen: Bool)
    case contentChanged(PanelContentStatus, pointerInsideKeepOpen: Bool)
    case pointerChanged(isInsideKeepOpen: Bool, at: TimeInterval)
    case exitDeadlineReached(PanelDeadline, isInsideKeepOpen: Bool, at: TimeInterval)
    case externalFocusLost(editSaveSucceeded: Bool?)
    case pinToggled(pointerInsideKeepOpen: Bool)
    case didReturnToCorner(pointerInsideKeepOpen: Bool)
    case closeRequested
    case didBeginClosing
    case didClose
}
```

`PanelStateMachine` internally remembers the unpinned content state underneath `.pinned` and `.error`, so clearing an error or unpinning can return to `.itemEditing`, `.draftLocked`, or `.openEmpty` without expanding the public state list.

## Standard Test Commands

Every slice first runs `git status --short` and `git diff --check`. Use this compile/red command after adding the new test membership:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing
```

Use this deterministic green command after the minimal implementation:

```bash
DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest \
  /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest
```

Expected GREEN after every slice: all prior tests plus the new slice pass with 0 failures. Do not accept “new tests pass but an earlier test fails.”

---

## Task 8.1: Extend the Existing Store into the Complete Lifecycle Seam

**Files:** Modify `CornerPet/Persistence/ItemStore.swift`, `CornerPetTests/ItemStoreTests.swift`; create `CornerPetTests/ItemLifecycleTests.swift`; modify `CornerPet.xcodeproj/project.pbxproj`.

- [ ] Add RED tests for generic bucket fetch ordering, inbox→favorite, favorite→inbox, archive→inbox undo, exact text update, wrong-source no-op, permanent delete, and every save-failure rollback.
- [ ] Verify RED: `build-for-testing` must fail because `ItemLifecycleStoring` and lifecycle methods are absent. A PBX parse error is not an acceptable RED.
- [ ] Implement one private fetch-by-ID helper and one save-with-rollback mutation path. Existing `fetchInbox`, `fetchArchive`, and `archiveInboxItem` become small compatibility wrappers over the new implementation; do not duplicate predicates/mutation rollback.
- [ ] Run the standard GREEN command.

Tests and real regressions:

| Test | Regression caught |
|---|---|
| `testFetchItemsFiltersBucketAndSortsMovedBucketsNewestFirst` | Archive/Favorites mixing buckets or sorting on `createdAt` instead of latest move |
| `testMoveInboxToFavoriteAndFavoriteBackToInboxPreservesCreatedAt` | Favorite behaving like a flag while the row remains in Inbox; creation date drift |
| `testMoveArchiveBackToInboxPersistsAcrossFreshContext` | Undo only changing an in-memory snapshot |
| `testMoveRejectsWrongExpectedSource` | Stale UI moving an item twice or resurrecting a deleted/moved record |
| `testUpdateTextPreservesCreatedAtAndMovedAtButChangesUpdatedAt` | Editing corrupting historical ordering/timestamps |
| `testFailedUpdateRollsBackExactOldTextAndTimestamps` | UI retaining text that was never durable |
| `testPermanentDeleteRemovesOnlyConfirmedID` | Broad delete predicate or wrong-row deletion |
| `testFailedDeleteKeepsItemInOriginalBucketInFreshContext` | SwiftData delete rollback failure with a false success claim |

**Rollback boundary:** only store/tests/PBX additions. If rollback semantics cannot be proven, stop before view-model work; do not add UI workarounds.

## Task 8.2: Add Exact Five-Second Archive Undo to the Existing Completion Path

**Files:** Create `CornerPet/Capture/ArchiveUndoController.swift`, `CornerPetTests/ArchiveUndoControllerTests.swift`; modify `InboxViewModel.swift`, `InboxViewModelTests.swift`, `InboxView.swift`, `CaptureCompositionRoot.swift`, PBX.

- [ ] Write RED tests with a manual monotonic clock/scheduler; never wait five seconds in a test.
- [ ] Verify RED: missing `ArchiveUndoController`/offer interface.
- [ ] After existing `complete` succeeds, remove the Inbox row, publish “Archived · Undo”, and schedule generation-tagged expiry at `now + 5.000`. Undo uses `.archive → .inbox`; success cancels expiry and restores newest-first Inbox ordering. Failure keeps the offer and shows an error.
- [ ] A second completion replaces the visible offer and invalidates its timer token; the earlier item remains archived.
- [ ] Run GREEN.

| Test | Regression caught |
|---|---|
| `testSuccessfulCompletionPublishesUndoForExactlyFiveSeconds` | Wrong duration or offer shown before persistence succeeds |
| `testUndoMovesArchivedItemBackAndCancelsExpiry` | Cosmetic undo that does not persist |
| `testExpiryAt4999msKeepsOfferAndAt5000msRemovesIt` | Off-by-one timer behavior |
| `testStaleExpiryCannotRemoveReplacementOffer` | Cancelled callback racing a newer archive action |
| `testUndoFailureKeepsOfferAndDoesNotClaimInboxRestore` | Data loss/false success on failed move |

**Rollback boundary:** undo controller plus inbox wiring; existing completion remains usable if this slice is reverted.

## Task 8.3: Complete Favorites and Locale-Aware Archive/Favorites Search

**Files:** Create `FavoritesViewModel.swift`, `FavoritesView.swift`, `LibrarySearch.swift`, `CornerPetTests/LibraryViewModelTests.swift`; modify `ArchiveViewModel.swift`, `ArchiveViewModelTests.swift`, `ArchiveView.swift`, `ItemRow.swift`, `InboxView.swift`, `CapturePanelView.swift`, `CaptureCompositionRoot.swift`, PBX.

- [ ] Write RED tests for favorite/removal callbacks, destination isolation, empty query, Chinese substring, Latin case/diacritic matching, and query clearing after a load retry.
- [ ] Verify RED: missing Favorites and `LibrarySearch` types.
- [ ] Implement `LibrarySearch.filter(_:query:)` using `query.isEmpty || item.text.localizedStandardContains(query)` exactly. Each library view model retains `allItems` and derives visible `items`; never destructively filter the source array.
- [ ] Inbox Favorite moves to `.favorite` and removes the row only after success. Removing Favorite moves to `.inbox` and removes it from Favorites only after success. Failures retain the row and expose an error.
- [ ] Add Archive/Favorites search fields and stable identifiers `archive.search` and `favorites.search`; Command-F focuses only the selected supported destination.
- [ ] Run GREEN.

| Test | Regression caught |
|---|---|
| `testSearchUsesLocalizedStandardContainsForChineseAndCaseDiacritics` | Hand-rolled lowercase matching breaking locale behavior |
| `testEmptySearchReturnsAllSourceItemsAfterPriorFiltering` | Clearing the query leaving a permanently truncated list |
| `testFavoriteSuccessRemovesInboxAndAppearsInFavorites` | Same item visible in two mutually exclusive buckets |
| `testFavoriteFailureLeavesInboxRowAndShowsError` | Optimistic removal after a failed save |
| `testUnfavoriteReturnsItemToInbox` | Cancel Favorite deleting or archiving the item |
| `testArchiveAndFavoritesNeverLeakEachOthersItems` | Shared view-model cache crossing destinations |

**Rollback boundary:** Favorites/search files and view wiring; archive load and inbox completion from Task 7 remain intact.

## Task 8.4: Add One Shared Inline Edit Session Across All Lists

**Files:** Create `ItemEditViewModel.swift`, `InlineItemEditor.swift`, `CornerPetTests/ItemEditViewModelTests.swift`; modify all three row/view models and rows/views, `CaptureCompositionRoot.swift`, `CapturePanelView.swift`, PBX.

- [ ] Write RED tests for double-click begin, Return, Shift-Return, Escape, focus-loss save, save failure, timestamps, and row-action locking.
- [ ] Verify RED: missing editor/session types.
- [ ] Implement one composition-owned `ItemEditViewModel`; only one item can be edited at a time. Beginning captures the immutable original and mutable working text. A list applies the returned durable snapshot by ID.
- [ ] `InlineItemEditor` uses AppKit key handling: Return commits without newline; Shift-Return calls native newline insertion; Escape cancels and restores original; `textDidEndEditing` attempts save. Marked-text/IME Return passes through AppKit.
- [ ] While an item is active, its completion/favorite/unfavorite/delete buttons are disabled. Double-clicking another row first attempts to save the active edit; failure keeps the current editor.
- [ ] On failure, retain working text, keep editor focused/open, publish the persistent save error, and report editing/error activity to Task 9's future composition seam.
- [ ] Run GREEN.

| Test | Regression caught |
|---|---|
| `testBeginKeepsOriginalUntilSaveOrCancel` | Mutating visible source snapshot before persistence |
| `testReturnSavesExactWorkingTextAndUpdatesOnlyUpdatedAt` | Timestamp corruption or accidental trimming |
| `testShiftReturnInsertsNewlineWithoutStoreCall` | Multiline edit submitting prematurely |
| `testEscapeRestoresOriginalAndKeepsPanelOpen` | Escape deleting edits or closing the entire panel |
| `testFocusLossSavesOnce` | Outside click causing duplicate saves |
| `testSaveFailureKeepsWorkingTextEditorAndError` | Failed edit silently reverting or closing |
| `testRowOperationsAreDisabledForActiveEdit` | Archive/favorite/delete racing the edit save |
| `testMarkedTextReturnDoesNotCommit` | Chinese IME candidate confirmation submitting the item |

**Rollback boundary:** shared editor and row adaptations. No store schema migration is involved.

## Task 8.5: Add Explicit Confirmed Permanent Deletion and Finish the Library UI Flow

**Files:** Modify inbox/archive/favorites view models and views/rows, `CapturePanelView.swift`; create `CornerPetUITests/LibraryFlowUITests.swift`; modify PBX.

- [ ] Write RED unit tests: request confirmation makes no store call; cancel leaves row; confirm deletes one row; failure retains row/error; delete is disabled during edit.
- [ ] Add XCUITest RED flows for archive+undo, favorite+unfavorite, both searches, edit Return/Shift-Return/Escape/outside save, action lock, confirm cancel/accept, and failed delete fixture.
- [ ] Verify RED: unit tests fail for missing confirmation state; UI test build succeeds but flows fail on missing identifiers/actions.
- [ ] Implement `.alert`/`.confirmationDialog` with explicit destructive confirmation and stable identifiers. Remove the row only when `deletePermanently` returns `true`; failure keeps the item and shows no success message.
- [ ] Run unit GREEN, then the UI command:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetUITests/LibraryFlowUITests test
```

Expected GREEN on a healthy runner: all Library flows pass. If worker materialization stalls before the first test, record it as infrastructure evidence, keep the successful UI-test build, and require Jack's matching manual flow; do not call the UI suite passed.

| Test | Regression caught |
|---|---|
| `testDeleteRequestRequiresSecondAction` | One-click irreversible deletion |
| `testDeleteCancellationNeverCallsStore` | Cancel still mutating persistence |
| `testConfirmedDeleteRemovesExactlyOneVisibleAndPersistedItem` | Wrong-row/broad deletion |
| `testDeleteFailureKeepsItemAndShowsError` | False success or disappearing row |
| `LibraryFlowUITests` | Wiring/accessibility/focus issues that view-model tests cannot observe |

### Task 8 Acceptance Gate

- [ ] Archive completion shows one 5-second undo; expiry and stale tokens are deterministic.
- [ ] Favorite removes Inbox row; unfavorite returns it to Inbox.
- [ ] Archive and Favorites use `localizedStandardContains` and Command-F.
- [ ] Inline edit supports Return, Shift-Return, Escape, inside/outside click save, failure retention, action lock, and IME safety.
- [ ] `createdAt`/`movedAt` remain; durable edit changes `updatedAt`.
- [ ] Permanent delete requires confirmation; cancel and failure retain the item.
- [ ] Existing 170 tests plus all Task 8 tests pass; UI evidence/manual fallback is recorded.
- [ ] Terra approves before Task 9 begins.

---

## Task 9.1: Introduce the Pure Eight-State Panel Reducer

**Files:** Create `CornerPet/Panel/PanelStateMachine.swift`, `CornerPetTests/PanelStateMachineTests.swift`; modify PBX.

- [ ] Write table-driven RED tests for every state/event pair and token edge.
- [ ] Verify RED: missing reducer types.
- [ ] Implement state precedence `pinned > error > itemEditing > draftLocked > openEmpty`; remember underlying content while pinned/error. Only `openEmpty` outside may emit a 120 ms schedule effect.
- [ ] Run GREEN.

Mandatory reducer tests and regressions:

| Test | Regression caught |
|---|---|
| `testPresentTransitionsHiddenOpeningOpenEmpty` | Window phase and content phase drifting |
| `testDraftAndEditExitNeverScheduleClose` | Draft/edit lost because pointer left |
| `testOpenEmptyExitSchedulesExactly120ms` | Wrong 100 ms prototype timing |
| `testReentryCancelsAndStaleDeadlineCannotClose` | Cancelled timer racing re-entry |
| `testErrorIgnoresExitAndExternalFocus` | Error disappearing before recovery |
| `testPinnedIgnoresExitAndExternalFocus` | Pinned window auto-hiding |
| `testExternalFocusClosesDraftPreservingContent` | External click submitting/clearing draft |
| `testExternalFocusEditSuccessClosesAndFailureStaysEditingInError` | Closing before edit durability |
| `testUnpinDraftOrEditReturnsToCornerAndStaysOpen` | Unpin discarding active work |
| `testUnpinEmptyOutsideReturnsThenCloses` | Empty unpinned panel stranded onscreen |
| `testClosingReentryEmitsOneReverse` | Repeated reversals/flicker |
| `testNonFiniteBackwardAndEarlyDeadlineNeverClose` | Invalid time causing dismissal |

**Rollback boundary:** new pure reducer/tests only; no runtime wiring yet.

## Task 9.2: Migrate 100 ms Prototype Close Ownership to the One 120 ms Lifecycle Coordinator

**Files:** Create `PanelLifecycleCoordinator.swift`, `CornerPetTests/PanelLifecycleCoordinatorTests.swift`; modify `HotCornerStateMachine.swift`, `CornerTriggerCoordinator.swift`, their tests, `AppDelegate.swift`, `CaptureCompositionRoot.swift`, PBX.

- [ ] Write RED adapter tests proving one pending timer maximum, deadline pointer recheck, generation rejection, trigger/panel union reconciliation, and content-state forwarding.
- [ ] Rewrite trigger RED expectations: no `.closeDebounce`, `.dismiss`, `dismissPanel`, `panelFrameProvider`, or `setAutoHideProtected`; the trigger still presents after 400 ms and reports trigger presence/retrigger during closing.
- [ ] Verify RED: old 100 ms tests fail and new lifecycle types are missing.
- [ ] Implement `PanelLifecycleCoordinator` as the only owner of `PanelDeadlineScheduling`; it feeds pure events, schedules/cancels exact tokens, rechecks the pointer at expiry, and calls controller effects.
- [ ] Remove close scheduling and content protection from trigger code, not merely disable it. Preserve stale dwell rejection and 400 ms tests.
- [ ] Wire content status from draft, shared edit, and persistent error state. A list-load error and save/delete error both map to `hasError` without disabling capture.
- [ ] Run GREEN and scan:

```bash
rg -n 'closeDebounce|0\.100|setAutoHideProtected|dismissPanel' \
  CornerPet/HotCorner/HotCornerStateMachine.swift \
  CornerPet/HotCorner/CornerTriggerCoordinator.swift
```

Expected: no old auto-hide ownership remains. Any `0.100` match elsewhere must be unrelated and reviewed.

| Test | Regression caught |
|---|---|
| `testOnlyLifecycleCoordinatorSchedulesPanelExitDeadline` | Double timer/competing close owners |
| `testUnionReentryCancelsBeforeDeadline` | Trigger-to-panel handoff closing the panel |
| `testDeadlineRechecksPointer` | Close after pointer returned without a boundary callback |
| `testContentChangeCancelsPendingEmptyClose` | User begins typing/editing while old timer remains live |
| `testTriggerStillPresentsAndReversesWithoutDismissing` | Migration breaking hot-corner opening/retrigger |

**Rollback boundary:** this migration is atomic. Do not leave both 100 and 120 ms paths compiled at a checkpoint.

## Task 9.3: Wire External Focus, Editing Save Outcome, Error Retention, and Escape

**Files:** Modify `CapturePanelController.swift`, `CornerPanel.swift`, `CaptureCompositionRoot.swift`, `AppDelegate.swift`, `CaptureCompositionTests.swift`, `PanelAnimatorTests.swift`.

- [ ] Add RED integration tests by directly invoking the `NSWindowDelegate` adapter: empty/draft closes appropriately, item edit saves before close, failed save remains, pinned/error ignore, Escape cancels edit but closes a new-draft panel preserving draft.
- [ ] Verify RED: old controller always dismisses Escape and has no external-focus adapter.
- [ ] Make responder ownership explicit: inline editor handles Escape first; otherwise capture input flushes/preserves and requests close. `windowDidResignKey` asks the shared editor to save, then sends success/failure to the lifecycle coordinator.
- [ ] On edit failure transition to `.error` while keeping editor and panel open; dismissing the error returns to `.itemEditing` until save/cancel resolves it.
- [ ] Run GREEN.

| Test | Regression caught |
|---|---|
| `testExternalClickWaitsForEditSaveBeforeClosing` | Window disappearing before persistence result |
| `testFailedExternalEditSaveKeepsFirstResponderAndPanel` | User losing unsaved changed text |
| `testEscapeCancelsItemEditWithoutClosing` | Root Escape probe swallowing editor contract |
| `testPinnedAndErrorIgnoreResignKey` | External focus bypassing state policy |

**Rollback boundary:** controller/composition adapter only; pure state machine remains independently valid.

## Task 9.4: Add Pin Toggle, Command-Shift-P, Movement, Resizing, and Size Persistence

**Files:** Create `PinnedPanelSizeStore.swift`, `CornerPetTests/PinnedPanelSizeStoreTests.swift`; modify `CornerPanel.swift`, `CapturePanelController.swift`, `CaptureHeaderView.swift`, `CapturePanelView.swift`, `CaptureCompositionRoot.swift`, `PanelAnimatorTests.swift`, PBX.

- [ ] Write RED tests for default size, min/max clamping, persistence across a fresh store adapter, button/shortcut parity, and pinned panel flags.
- [ ] Verify RED: missing size store and pin interface.
- [ ] Store only width/height under a namespaced UserDefaults key; clamp on read and write to 280×320...480×640. Inject an isolated suite in tests.
- [ ] When pinned, set movable/background-drag and resizable behavior, `contentMinSize`, `contentMaxSize`, and retain floating/full-screen auxiliary collection behavior. Persist size from resize completion, not every layout pass.
- [ ] Route header button and Command-Shift-P through the same `togglePin()` method. Implement the shortcut in the panel responder/`performKeyEquivalent` path so capture and inline text views do not swallow it.
- [ ] Make `CapturePanelView` fill the host size rather than hard-coding 360×450, while keeping its capture/list/nav regions intact.
- [ ] Run GREEN.

| Test | Regression caught |
|---|---|
| `testPinnedSizeDefaultsTo360x450AndClampsBothAxes` | Invalid UserDefaults making the window unusable |
| `testPinnedSizePersistsAcrossFreshAdapter` | Size only retained in controller memory |
| `testPinnedPanelIsMovableResizableWithinExactBounds` | Unbounded or immovable pin mode |
| `testCommandShiftPAndButtonCallSameToggle` | Shortcut and UI diverging |
| `testPinKeepsFloatingFullscreenAuxiliaryBehavior` | Pinning breaking full-screen access |

**Rollback boundary:** size store and pin adaptations; no display/corner setting is introduced.

## Task 9.5: Animate Unpin Return and Close Only the Empty Outside Case

**Files:** Modify `CapturePanelController.swift`, `PanelAnimator.swift` only if the existing sampler cannot animate frame-to-frame return, `PanelPositioner.swift`, related tests; create `CornerPetUITests/PinningFlowUITests.swift`; modify PBX.

- [ ] Write RED tests for return target at configured corner/current retained size, draft/edit stay-open, empty-inside stay-open, empty-outside return-then-close, and close reversal during return.
- [ ] Verify RED: controller currently has no pin/unpin path.
- [ ] Reuse the accepted damped spring language for the return. Do not change 260/180 ms open/close constants. The state machine requests close only after the controller reports `didReturnToCorner` and confirms the pointer remains outside.
- [ ] Run unit GREEN, then UI:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetUITests/PinningFlowUITests test
```

Expected: pin button and Command-Shift-P toggle observable pinned state; pinned ignores hover exit. Movement/resizing and exact return geometry remain Jack manual checks because XCUITest window drag/resize is not reliable enough to be the only evidence.

| Test | Regression caught |
|---|---|
| `testUnpinReturnsToConfiguredCornerWithRetainedSize` | Unpin changing trigger corner or losing size |
| `testUnpinDraftAndEditStayOpen` | Active work lost during return |
| `testUnpinEmptyOutsideClosesOnlyAfterReturnCompletes` | Flicker/snap/close at old location |
| `testUnpinEmptyInsideStaysOpen` | Closing despite active pointer presence |

### Task 9 Acceptance Gate

- [ ] All eight named states are reachable and exhaustively tested.
- [ ] Empty unpinned exit schedules one 120 ms close; re-entry/content change cancels; stale callbacks are inert.
- [ ] Draft/edit exit does not close; error remains; pinned ignores exit and external focus.
- [ ] External click saves edit before closing; failure stays open with working text.
- [ ] Pin button and Command-Shift-P share one path.
- [ ] Pinned panel moves/resizes only within 280×320...480×640 and size survives relaunch.
- [ ] Unpin returns to configured corner; draft/edit remain; empty/outside closes after return.
- [ ] Trigger code contains no 100 ms auto-hide owner; 400 ms dwell and reversal tests remain green.
- [ ] Full direct unit suite and Debug build pass; UI runner result is honestly recorded.

---

## Verification Ownership

| Must be deterministic unit/integration XCTest | Must be XCUITest | Must be Jack real-Mac manual |
|---|---|---|
| Store transitions/rollback/timestamps; 5 s token/expiry; search semantics; edit state/key policy; delete confirmation state; every panel transition; 120 ms/stale token; size clamp/persistence; shortcut dispatch; controller effect ordering | Visible archive undo; Favorite/unfavorite; both search fields and Command-F; inline edit Return/Shift-Return/Escape/click elsewhere; disabled actions; confirmation cancel/accept/failure; pin button/shortcut observable state | Hover timing feel; outside click into Finder/Safari; drag by panel background; resize at all four bounds; relaunch size; unpin spring/return; empty outside close; draft/edit stay; Finder/Safari/Xcode/full-screen video and Spaces; no invisible click blocker |

XCUITest does not replace unit timing tests, and unit tests do not prove AppKit focus, window level, drag, resize, or full-screen behavior.

## Jack Manual Matrix

- [ ] Finder normal window: empty exit/re-entry around 120 ms; external click with draft; external click with successful/failed edit.
- [ ] Safari and Xcode full-screen Spaces: open, pin, type/edit, switch focus, unpin, close without exiting full screen.
- [ ] Pin using button and Command-Shift-P from capture input and inline editor.
- [ ] Drag pinned panel; resize to 280×320 and 480×640; attempt beyond each bound.
- [ ] Quit/relaunch and confirm last pinned size returns.
- [ ] Unpin while draft active, edit active, error active, empty+inside, and empty+outside.
- [ ] Rapid exit/re-entry and trigger re-entry during closing; no double close, snap, flicker, or dead click surface.
- [ ] Archive/Favorite searches with Chinese and mixed-case Latin; long multiline edit; delete cancel/confirm/failure fixture.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| SwiftData rollback after delete/update leaves context inconsistent | Fresh-context tests after every injected save failure; one mutation helper |
| Divergent inbox/archive/favorite caches | Apply durable snapshot by ID and refetch destination on navigation; no shared mutable model objects in views |
| Focus-loss save fires twice | One edit session revision and `isSaving` guard; test exact call count |
| IME Return submits | Both AppKit editors check `hasMarkedText()` first |
| 100/120 ms race | Atomic Task 9.2 migration and scan proving old close owner is gone |
| Flat `.pinned`/`.error` loses draft/edit context | State machine stores underlying unpinned content internally and tests restoration |
| Nonactivating panel external-focus callbacks vary by app/Space | Unit-test adapter contract plus required Finder/Safari/Xcode manual matrix |
| UserDefaults corrupt/out-of-range size | Validate finite positive values and clamp both axes on read/write |
| Hard-coded 360×450 SwiftUI frame blocks resize | Task 9.4 makes root adaptive before claiming resize works |
| UI runner stalls before execution | Preserve build/unit evidence, record stall, require exact manual flows; never report UI PASS without executed cases |
| PBX conflicts in dirty worktree | One slice adds only its own references; inspect PBX diff and signing settings each gate |

## Rollback Policy

- Each numbered slice is a rollback boundary. Revert only files/lines introduced by that slice; never reset the worktree.
- Store evolution is additive and has no schema change; Task 8 UI can roll back without deleting persisted data.
- Task 9.2 is the sole atomic boundary: old 100 ms close ownership and new 120 ms ownership may not coexist in a checked/reviewed state.
- Pin size persistence uses a new namespaced defaults key; rolling back Task 9 leaves harmless local preferences, not content corruption.
- If a slice fails Terra review, stop there. Do not compensate with Task 10 display/settings code or visual polish.

## Luna Implementation Handoff

1. Re-read both specs and this plan, then run the baseline commands. If current tests are not green, report the baseline defect before editing.
2. Execute strictly 8.1→8.5, obtain Terra Task 8 gate, then 9.1→9.5. Do not batch store/UI/panel migrations.
3. For each slice: add one failing behavior test, run RED, implement the minimum, run full direct XCTest, inspect diff, then request review. A compile failure from a broken PBX file is not RED.
4. Use injected clocks/schedulers/UserDefaults suites. No sleeps, polling, global mouse monitors, singleton test state, or production-only conditionals.
5. Preserve existing compatibility wrappers and tests until the new seam is green. Remove duplicated behavior only within the same reviewed slice.
6. Do not mark XCUITest green if it only built or stalled before test execution. Attach the exact last runner phase and hand the corresponding manual row to Jack.
7. Do not commit, push, or create a PR. Report changed files and verification evidence only.

## Terra Review Checklist

- [ ] Diff is limited to the current slice and preserves all prior dirty changes/signing.
- [ ] Existing archive foundation is extended, not duplicated.
- [ ] Every store mutation saves before UI success and rolls back on failure.
- [ ] Search calls `localizedStandardContains` and preserves unfiltered source data.
- [ ] Edit exact text/timestamps, IME, Escape, focus-loss, failure retention, and operation disabling are proven.
- [ ] Delete requires explicit confirmation and failed delete leaves durable/visible data.
- [ ] `PanelStateMachine` alone decides close eligibility; `PanelLifecycleCoordinator` alone schedules its 120 ms token.
- [ ] Trigger coordinator has no remaining panel auto-hide timer/content-protection policy.
- [ ] Pinned/error precedence and underlying draft/edit restoration are deterministic.
- [ ] Command-Shift-P, move/resize bounds, persistence, unpin return, and adaptive content are verified.
- [ ] Tests state the real regression they guard and avoid internal implementation assertions where observable outcomes suffice.
- [ ] No Task 10+ display settings, reminder, localization overhaul, UI redesign, network, cloud, or third-party scope entered.

## Final Verification

```bash
git diff --check

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData build-for-testing

DYLD_LIBRARY_PATH=/Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/MacOS \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xctest \
  /Users/jack/MyApp/CornerPet/DerivedData/Build/Products/Debug/CornerPet.app/Contents/PlugIns/CornerPetTests.xctest

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetUITests/LibraryFlowUITests \
  -only-testing:CornerPetUITests/PinningFlowUITests test

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData build
```

Expected: no whitespace errors; all unit/integration tests execute with zero failures; both UI suites execute and pass or the pre-execution infrastructure stall is explicitly recorded; arm64 Debug ends `BUILD SUCCEEDED`; Jack completes the manual matrix before Task 9 is reported complete.

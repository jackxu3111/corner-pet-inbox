# CornerPet MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task. Track every step with checkboxes.

**Goal:** Deliver a native arm64 macOS app that captures a thought through an invisible L-shaped corner trigger, preserves drafts, and manages a local inbox.

**Architecture:** SwiftUI renders product UI; AppKit adapts pointer, panel, full-screen, Spaces, and displays; SwiftData persists Draft and IdeaItem. Geometry, dwell, panel lifecycle, and reminders remain deterministic state machines.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SwiftData, ServiceManagement, XCTest, XCUITest

**Spec:** docs/superpowers/specs/2026-08-25-hot-corner-capture-interaction-design.md

## Global Constraints

- macOS 14.0 minimum; arm64 only.
- Default corner top-left; geometry uses 86 pt arms and 6 pt thickness.
- Dwell is fixed at 400 ms; no alternative presets.
- Panel 360×450 pt; pinned range 280×320 through 480×640 pt.
- Open/close 260/180 ms; Reduce Motion 120 ms.
- Local-only content; no text analytics, accounts, network, or third-party dependencies.
- Full-screen and Spaces must work before feature expansion.
- No commits, pushes, or PRs without Jack's explicit authorization.

## File Structure

~~~text
CornerPet/App/             lifecycle, coordinator, constants
CornerPet/HotCorner/       geometry, dwell state, mouse adapter
CornerPet/Panel/           NSPanel, placement, animation, state
CornerPet/Persistence/     Draft, IdeaItem, stores, container
CornerPet/Capture/         input-first UI, submission, inbox
CornerPet/Library/         archive, favorites, search, edit
CornerPet/Settings/        settings, hot-corner help, login launch
CornerPet/Reminder/        policy, scheduler, cat panel
CornerPet/Metrics/         content-free local metrics
CornerPet/Resources/       String Catalog
CornerPetTests/            unit and integration tests
CornerPetUITests/          user-flow tests
docs/qa/                   manual matrix
docs/validation/           seven-day dogfood
~~~

## Stable Contracts

~~~swift
enum TriggerCorner: String, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
enum DwellTiming { static let duration: TimeInterval = 0.4 }
enum DisplayScope: String, CaseIterable { case primary, all }
enum ItemBucket: String, Codable { case inbox, archive, favorite }

struct ScreenDescriptor: Identifiable, Equatable {
    let id: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let isPrimary: Bool
}
~~~

---

### Task 1: Project Baseline

**Files:** Create CornerPet.xcodeproj, CornerPet/App/CornerPetApp.swift, AppDelegate.swift, AppConfiguration.swift; test AppConfigurationTests.swift.

- [ ] Write a failing test for minimum major version 14 and product names CornerPet/角落灵感箱.
- [ ] Run the focused xcodebuild test; expect missing AppConfiguration.
- [ ] Add constants, macOS 14 deployment, arm64 Debug/Release, accessory activation, Unit/UI Test targets.
- [ ] Run clean test and Release build; expect PASS and BUILD SUCCEEDED.

### Task 2: Four L-shaped Trigger Geometries

**Files:** Create HotCorner/HotCornerGeometry.swift, TriggerCorner.swift; test HotCornerGeometryTests.swift.

- [ ] Test every corner returns two 86×6 pt rectangles sharing that corner; test overlap, edge inclusion, and outside 0.1 pt exclusion.
- [ ] Implement:

~~~swift
struct HotCornerGeometry {
    static func regions(frame: CGRect, corner: TriggerCorner) -> [CGRect] {
        let arm: CGFloat = 86
        let thickness: CGFloat = 6
        switch corner {
        case .topLeft:
            return [
                CGRect(x: frame.minX, y: frame.maxY-thickness, width: arm, height: thickness),
                CGRect(x: frame.minX, y: frame.maxY-arm, width: thickness, height: arm)
            ]
        case .topRight:
            return [
                CGRect(x: frame.maxX-arm, y: frame.maxY-thickness, width: arm, height: thickness),
                CGRect(x: frame.maxX-thickness, y: frame.maxY-arm, width: thickness, height: arm)
            ]
        case .bottomLeft:
            return [
                CGRect(x: frame.minX, y: frame.minY, width: arm, height: thickness),
                CGRect(x: frame.minX, y: frame.minY, width: thickness, height: arm)
            ]
        case .bottomRight:
            return [
                CGRect(x: frame.maxX-arm, y: frame.minY, width: arm, height: thickness),
                CGRect(x: frame.maxX-thickness, y: frame.minY, width: thickness, height: arm)
            ]
        }
    }
}
~~~

- [ ] Run HotCornerGeometryTests; expect all four rotations PASS.

### Task 3: Dwell State and Mouse Adapter

**Files:** Create HotCorner/DwellTiming.swift, HotCornerStateMachine.swift, MouseMonitor.swift; test HotCornerStateMachineTests.swift.

- [ ] Test 399 ms does not trigger and 400 ms does; movement inside either arm preserves timer; exit resets; show occurs once; 80 ms post-close debounce applies.
- [ ] Model actions as none, present(screenID), and reverseClosing(screenID). Inject time and regions.
- [ ] Adapt NSEvent global and local mouseMoved monitors. Do not monitor keys or request Accessibility.
- [ ] Run tests; manually verify events while CornerPet is active and inactive.

### Task 4: Full-screen Panel and Reversible Animation Prototype

**Files:** Create Panel/CornerPanel.swift, PanelPositioner.swift, PanelAnimator.swift, CapturePanelController.swift; test PanelPositionerTests.swift and PanelAnimatorTests.swift.

- [ ] Test 360×450 placement flush with each selected visible corner.
- [ ] Configure a key-capable borderless NSPanel at floating level with canJoinAllSpaces, fullScreenAuxiliary, transient, and ignoresCycle.
- [ ] Animate shell 260 ms from selected-corner capsule; fade content separately; close 180 ms; reverse current progress when retriggered.
- [ ] When Reduce Motion is enabled, use 120 ms fade/scale without overshoot.
- [ ] Verify Finder, Safari/Xcode full screen, Spaces, focus acquisition/restoration, and no hidden click blocker.
- [ ] Stop for Checkpoint A approval before Task 5.

### Task 5: Draft and Item Persistence

**Files:** Create Persistence/Draft.swift, IdeaItem.swift, ModelContainerFactory.swift, DraftStore.swift, ItemStore.swift; tests DraftStoreTests.swift and ItemStoreTests.swift.

- [ ] Write in-memory SwiftData tests for singleton draft upsert/restore, trimmed formal item capture, duplicate allowance, bucket moves, search, update, and permanent delete.
- [ ] Draft fields: text, updatedAt. IdeaItem fields: id, text, bucketRawValue, createdAt, updatedAt, movedAt.
- [ ] DraftStore debounces writes briefly and exposes flush(); ItemStore saves every mutation.
- [ ] Clear Draft only after ItemStore capture succeeds.
- [ ] Run persistence tests and manual quit/relaunch recovery.

### Task 6: Conditional Submission and Persistent Errors

**Files:** Create Capture/CaptureViewModel.swift, SaveErrorView.swift; test CaptureViewModelTests.swift and CaptureSubmissionIntegrationTests.swift.

- [ ] Test Return success with pointer inside stays open; outside closes; pinned stays open. Test failure retains draft, panel, and retryable error.
- [ ] Test Shift-Return inserts newline and Escape closes while preserving new draft.
- [ ] Wire auto-focus and restored insertion point at draft end.
- [ ] Error remains until retry, success, or dismissal and never covers input.
- [ ] Run focused and integration tests.

### Task 7: Capture-first Inbox

**Files:** Create Capture/CapturePanelView.swift, InboxView.swift, ItemRow.swift, InboxViewModel.swift; test InboxViewModelTests.swift and CaptureFlowUITests.swift.

- [ ] Implement fixed header, one-to-five-line input, independently scrolling newest-first inbox, and fixed bottom navigation.
- [ ] New successful item appears at top without reopening.
- [ ] Hover reveals favorite/delete; checkbox is always visible.
- [ ] Run view-model tests and UI capture flow.

### Task 8: Archive, Undo, Favorites, Search, and Edit

**Files:** Create Library/ArchiveView.swift, FavoritesView.swift, LibraryViewModel.swift, InlineItemEditor.swift; test ItemLifecycleTests.swift and LibraryFlowUITests.swift.

- [ ] Test archive plus five-second undo, favorite and return-to-inbox, case-insensitive search, confirmed permanent delete.
- [ ] Test double-click edit: Return save, Shift-Return newline, Escape restore original, outside click save; failed save keeps editor.
- [ ] Disable row actions during edit and preserve createdAt while changing updatedAt.
- [ ] Run lifecycle and UI tests.

### Task 9: Complete Panel Lifecycle and Pinning

**Files:** Create Panel/PanelStateMachine.swift; modify CapturePanelController.swift; test PanelStateMachineTests.swift.

- [ ] Test hidden, opening, openEmpty, draftLocked, itemEditing, pinned, error, and closing transitions.
- [ ] Empty pointer exit starts 120 ms close; re-entry cancels. Draft/edit pointer exit does nothing.
- [ ] Pinned ignores exit/external focus, moves/resizes within 280×320–480×640, and persists size.
- [ ] Unpin returns to configured corner; draft/edit stays open; empty/outside closes.
- [ ] Verify Command-Shift-P and no flicker.

### Task 10: Corners and Multiple Displays

**Files:** Create HotCorner/ScreenCoordinator.swift, ScreenProvider.swift; modify panel positioning; test ScreenCoordinatorTests.swift.

- [ ] Test primary/all selection, shared corner, single panel, trigger-screen placement, and pinned-screen disconnect fallback.
- [ ] Rebuild descriptors on NSApplication.didChangeScreenParametersNotification; never cache NSScreen.
- [ ] While pinned, other-screen trigger fronts but does not move the panel.
- [ ] Complete built-in/external-left/external-right/scaling/disconnect matrix.

### Task 11: Settings, Conflict Help, and Login Launch

**Files:** Create Settings/AppSettings.swift, SettingsView.swift, HotCornerHelpView.swift, LaunchAtLoginController.swift; test AppSettingsTests.swift.

- [ ] Test defaults top-left, fixed 400 ms dwell, primary display, 360×450, reminder 09:00.
- [ ] Persist corner, display scope, last size, reminder, language.
- [ ] Wrap SMAppService.mainApp register/unregister; UI reflects real status and failures.
- [ ] Explain System Settings → Desktop & Dock → Hot Corners; never read/change private settings.
- [ ] Verify logout/login hidden startup.

### Task 12: Daily Reminder and Cat

**Files:** Create Reminder/ReminderPolicy.swift, ReminderScheduler.swift, PetReminderPanelController.swift, CatReminderView.swift; test ReminderPolicyTests.swift.

- [ ] Test before/after schedule, same-day suppression, disabled, ten-minute snooze, and wake-after-schedule.
- [ ] Evaluate at launch, once per minute, on wake, and settings changes; persist lastFiredAt before display.
- [ ] Draw an original cat from SwiftUI primitives; actions open inbox or snooze.
- [ ] Verify no repeated wake spam.

### Task 13: Localization, Accessibility, and Reduced Motion

**Files:** Create Resources/Localizable.xcstrings; test LocalizationUITests.swift; modify all user-facing views.

- [ ] Add zh-Hans/en values for capture, lists, errors, confirmation, settings, reminder, help, undo, and editing.
- [ ] Add stable identifiers for capture.input, capture.pin, library tabs/search, settings, reminder actions.
- [ ] Verify VoiceOver labels, keyboard shortcuts, Chinese/English layout, and Reduce Motion.
- [ ] Run both language UI suites.

### Task 14: Private Metrics, QA, and Release

**Files:** Create Metrics/LocalUsageMetrics.swift, tests LocalUsageMetricsTests.swift, docs/qa/macos-compatibility-matrix.md, docs/validation/seven-day-dogfood.md.

- [ ] Metrics accept durations and counts only: capture time/count, false trigger, reminder shown/snoozed. No String or IdeaItem input.
- [ ] Run:

~~~bash
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -destination 'platform=macOS,arch=arm64' clean test
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet -configuration Release -destination 'platform=macOS,arch=arm64' build
~~~

- [ ] Complete Finder, full-screen apps, Spaces, Stage Manager, displays, sleep, login, languages, and Reduce Motion matrix.
- [ ] Start seven-day dogfood: median capture ≤3 seconds, average ≥5/day, acceptable false triggers, reminders remain enabled.

## Self-Review

- Tasks 2–4 cover geometry, timing, full-screen, focus, animation, and the first gate.
- Tasks 5–8 cover draft, conditional save, layout, item lifecycle, edits, errors, and shortcuts.
- Tasks 9–12 cover panel state, pinning, displays, settings, login, conflicts, reminders, and cat.
- Tasks 13–14 cover localization, accessibility, reduced motion, privacy, QA, and release.
- Stable names align across tasks: TriggerCorner, DwellTiming, DisplayScope, ItemBucket, ScreenDescriptor.
- No Not Doing item is introduced.

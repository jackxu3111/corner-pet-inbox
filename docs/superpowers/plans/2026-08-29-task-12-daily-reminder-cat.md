# Task 12 Daily Reminder and Cat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a persistent, permissionless daily cat reminder with ten-minute snooze, sleep/wake recovery, four-corner multi-display positioning, and safe capture-panel integration.

**Architecture:** A pure `ReminderPolicy` decides behavior from explicit inputs. A main-actor `ReminderScheduler` owns persistence, minute evaluation, and system lifecycle observers. A separate `PetReminderPanelController` hosts a SwiftUI-drawn `CatReminderView` without entering the capture panel's state machine.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, Foundation Calendar, UserDefaults, XCTest, XCUITest, macOS 14+, arm64

**Spec:** `docs/superpowers/specs/2026-08-29-task-12-daily-reminder-cat-design.md`

## Global Constraints

- Work only in `/Users/jack/.codex/worktrees/ce75/CornerPet` at baseline `c3b7f1e`.
- Do not write to `/Users/jack/MyApp/CornerPet`.
- Do not commit, push, merge, reset, or discard changes without Jack's explicit authorization.
- Preserve hidden startup except when a due reminder legitimately presents the cat.
- Preserve capture, draft, edit, archive, favorites, pinning, four-corner, multi-display, full-screen, and launch-at-login behavior.
- Do not add system notifications, Input Monitoring, global shortcuts, a Dock icon, a menu-bar item, third-party dependencies, or external visual assets.
- Keep current paired Chinese/English copy; full localization remains Task 13.
- Persist a normal reminder before displaying it and clear a due snooze before displaying it.

---

### Task 1: Reminder Settings and Persistent State

**Files:**
- Modify: `CornerPet/Settings/AppSettings.swift`
- Create: `CornerPet/Reminder/ReminderStateStore.swift`
- Modify: `CornerPetTests/AppSettingsTests.swift`
- Create: `CornerPetTests/ReminderStateStoreTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `UserDefaults` and the existing typed `AppSettingsChange` flow.
- Produces: `AppSettings.reminderEnabled`, `ReminderConfiguration`, `ReminderState`, and `ReminderStateStore.load()/saveLastFiredAt(_:)/saveSnoozedUntil(_:)`.

- [ ] **Step 1: Add failing AppSettings tests for default-on, persistence, snapshots, and typed publication**

```swift
func testReminderIsEnabledByDefaultAndPersists() {
    let defaults = isolatedDefaults()
    let settings = AppSettings(defaults: defaults)
    XCTAssertTrue(settings.reminderEnabled)

    settings.setReminderEnabled(false)

    XCTAssertFalse(AppSettings(defaults: defaults).reminderEnabled)
}
```

- [ ] **Step 2: Add failing state-store tests for absent state, dates, snooze clearing, and isolated keys**

```swift
func testDatesRoundTripAndSnoozeCanBeCleared() {
    let defaults = isolatedDefaults()
    let store = ReminderStateStore(defaults: defaults)
    let fired = Date(timeIntervalSince1970: 100)
    let snoozed = Date(timeIntervalSince1970: 700)

    store.saveLastFiredAt(fired)
    store.saveSnoozedUntil(snoozed)
    XCTAssertEqual(store.load(), ReminderState(lastFiredAt: fired, snoozedUntil: snoozed))

    store.saveSnoozedUntil(nil)
    XCTAssertEqual(store.load().lastFiredAt, fired)
    XCTAssertNil(store.load().snoozedUntil)
}
```

- [ ] **Step 3: Run focused tests and confirm the new interfaces are missing**

Run:

```bash
xcodebuild test -project CornerPet.xcodeproj -scheme CornerPet -destination 'platform=macOS,arch=arm64' -only-testing:CornerPetTests/AppSettingsTests -only-testing:CornerPetTests/ReminderStateStoreTests
```

Expected: compilation fails because `reminderEnabled`, `ReminderState`, and `ReminderStateStore` do not exist.

- [ ] **Step 4: Implement the minimal setting and state store**

Add these stable shapes:

```swift
struct ReminderConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let dailyMinutes: Int
}

struct ReminderState: Equatable, Sendable {
    let lastFiredAt: Date?
    let snoozedUntil: Date?
}
```

Add `reminderEnabled` to `AppSettingsSnapshot`, `AppSettingsField`, loading, mutation, and publication. Use `UserDefaults.object(forKey:) as? NSNumber` so an absent value defaults to `true` while an explicitly persisted `false` remains false.

- [ ] **Step 5: Add project references and run both focused suites until green**

- [ ] **Step 6: Run existing AppSettings tests and inspect the scoped diff without committing**

---

### Task 2: Pure Calendar-Aware Reminder Policy

**Files:**
- Create: `CornerPet/Reminder/ReminderPolicy.swift`
- Create: `CornerPetTests/ReminderPolicyTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ReminderConfiguration`, `ReminderState`, injected `Calendar`, current `Date`, `isCaptureVisible`, and `isReminderVisible`.
- Produces: `ReminderPolicy.evaluate(_:) -> ReminderDecision` and `ReminderPolicy.scheduledDate(on:dailyMinutes:calendar:)`.

- [ ] **Step 1: Write the core failing decision matrix**

Cover before, exactly at, and after the configured time; disabled; same-day suppression; capture-visible handling; cat-visible deduplication; snooze before/due; and due snooze with capture visible.

```swift
let decision = ReminderPolicy.evaluate(ReminderPolicyInput(
    now: date("2026-08-29 09:00", in: shanghai),
    configuration: .init(isEnabled: true, dailyMinutes: 540),
    state: .init(lastFiredAt: nil, snoozedUntil: nil),
    calendar: calendar(timeZone: shanghai),
    isCaptureVisible: false,
    isReminderVisible: false
))
XCTAssertEqual(decision, .presentNormal(firedAt: date("2026-08-29 09:00", in: shanghai)))
```

- [ ] **Step 2: Run `ReminderPolicyTests` and verify missing-type failures**

- [ ] **Step 3: Implement the policy with deterministic precedence**

Use this public decision surface:

```swift
enum ReminderDecision: Equatable, Sendable {
    case none
    case clearSnooze
    case handleNormalWithoutPresentation(firedAt: Date)
    case consumeSnoozeWithoutPresentation
    case presentNormal(firedAt: Date)
    case presentSnoozed
}
```

Compute today's schedule with `Calendar.date(bySettingHour:minute:second:of:matchingPolicy:repeatedTimePolicy:direction:)` using `.nextTime`, `.first`, and `.forward`. Compare `lastFiredAt` using the injected calendar's local-day semantics.

- [ ] **Step 4: Run the core matrix until green**

- [ ] **Step 5: Add failing time-zone and DST tests**

Use fixed `Asia/Shanghai` and `America/Los_Angeles` calendars to prove:

- the same absolute `lastFiredAt` is interpreted in the current local day;
- `2026-03-08 02:30` in Los Angeles advances to the next valid local time;
- `2026-11-01 01:30` chooses the first repeated occurrence;
- the first occurrence records the day and suppresses the second occurrence;
- a snooze crossing midnight remains an absolute ten-minute deadline.

- [ ] **Step 6: Run `ReminderPolicyTests` until all calendar cases pass**

- [ ] **Step 7: Review the policy interface for side effects and confirm it imports Foundation only**

---

### Task 3: Lifecycle-Aware Reminder Scheduler

**Files:**
- Create: `CornerPet/Reminder/ReminderScheduler.swift`
- Create: `CornerPetTests/ReminderSchedulerTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ReminderPolicy`, `ReminderStateStore`, injected time/calendar/timer adapters, default and workspace notification centers, capture/reminder visibility providers, and presentation callbacks.
- Produces: `start(configuration:)`, `update(configuration:)`, `evaluate(reason:)`, `snooze()`, `completeCurrentReminder()`, and `stop()`.

- [ ] **Step 1: Define test adapters and write failing launch/minute/settings tests**

Use a manual repeating scheduler and isolated `NotificationCenter` instances. Assert that start evaluates once, schedules minute checks only while enabled, and time/enabled updates evaluate immediately.

- [ ] **Step 2: Write failing persistence-order tests**

```swift
var events: [String] = []
stateStore.onWrite = { events.append("persist") }
scheduler.onPresent = { _ in events.append("present") }

scheduler.start(configuration: .init(isEnabled: true, dailyMinutes: 540))

XCTAssertEqual(events, ["persist", "present"])
```

Also assert that due snooze clearing precedes `.snoozed` presentation.

- [ ] **Step 3: Run `ReminderSchedulerTests` and verify missing-interface failures**

- [ ] **Step 4: Implement scheduler startup, updates, policy application, and actions**

Use these reason and presentation values:

```swift
enum ReminderEvaluationReason: Equatable, Sendable {
    case launch
    case minute
    case wake
    case calendarChanged
    case clockChanged
    case timeZoneChanged
    case settingsChanged
}

enum ReminderPresentation: Equatable, Sendable {
    case normal
    case snoozed
}
```

The scheduler must persist the policy mutation synchronously before invoking `onPresent`.

- [ ] **Step 5: Add and pass wake, clock, time-zone, and calendar-day observer tests**

Register wake only on the injected workspace notification center. Register `.NSCalendarDayChanged`, `.NSSystemClockDidChange`, and `.NSSystemTimeZoneDidChange` on the injected default center. Post each notification and assert the exact evaluation reason.

- [ ] **Step 6: Add and pass repeated-wake and disabled cleanup tests**

After the first wake presentation, post wake again and assert no second presentation. Disabling must clear snooze and remove the minute timer while retaining lifecycle observers for future re-enable updates.

- [ ] **Step 7: Add and pass stop/deallocation tests**

Assert `stop()` cancels the timer, removes observers, and prevents later notifications from evaluating.

- [ ] **Step 8: Run policy, scheduler, and state-store suites together**

---

### Task 4: Four-Corner Cat Edge Rail

**Files:**
- Create: `CornerPet/Reminder/PetReminderPositioner.swift`
- Create: `CornerPet/Reminder/PetReminderPanelController.swift`
- Create: `CornerPet/Reminder/CatReminderView.swift`
- Create: `CornerPetTests/PetReminderPositionerTests.swift`
- Create: `CornerPetTests/PetReminderPanelControllerTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `[ScreenSnapshot]`, primary display ID, pointer location, `TriggerCorner`, SwiftUI action closures, and Reduce Motion state.
- Produces: a singleton nonactivating cat panel, `present(corner:screens:primaryDisplayID:)`, `updatePlacement(...)`, `dismiss()`, `isVisible`, and `currentScreenID`.

- [ ] **Step 1: Write failing pure positioning tests for all four corners**

Assert `240×300` frames attach to the correct visible edge, use top/bottom alignment, stay inside the visible frame, and leave the screen's 86-point corner trigger region clear.

- [ ] **Step 2: Add failing current-pointer screen and primary-fallback tests**

Use two synthetic displays and assert pointer containment wins even when display scope is primary. With a pointer outside every screen, assert primary then first-screen fallback.

- [ ] **Step 3: Implement `PetReminderPositioner` and run its tests green**

- [ ] **Step 4: Write failing controller tests for singleton, no activation, dismissal, and relocation**

Create the panel twice and assert one panel instance remains. Assert presentation uses `orderFrontRegardless()` without `makeKey()`, dismissal orders out, and screen removal relocates to the fallback display.

- [ ] **Step 5: Implement the panel controller with injected panel and hosting factories**

The production panel is borderless, nonactivating, transparent, available in all Spaces and full-screen auxiliary spaces, and shown without activating `NSApp`.

- [ ] **Step 6: Implement `CatReminderView` from native SwiftUI primitives**

Create focused subviews `CatFaceView`, `CatBodyView`, and `CatPawView` in the same feature folder. Provide real `Button` labels and identifiers:

```text
reminder.openInbox
reminder.snooze
reminder.dismissToday
reminder.panel
```

Use semantic fonts and styles. Treat the drawing as decorative for VoiceOver and expose one combined “CornerPet daily reminder” label on the surrounding reminder content.

- [ ] **Step 7: Add a lightweight edge-peek/paw animation with Reduce Motion opacity fallback**

- [ ] **Step 8: Run positioning and panel-controller tests plus an arm64 Debug build**

---

### Task 5: Settings, Composition, Capture Conflict, and UI Flows

**Files:**
- Modify: `CornerPet/Settings/CornerPetSettingsView.swift`
- Modify: `CornerPet/App/AppDelegate.swift`
- Modify: `CornerPet/App/CornerPetApp.swift`
- Modify: `CornerPet/App/AppConfiguration.swift`
- Modify: `CornerPet/Capture/CaptureCompositionRoot.swift`
- Modify: `CornerPetTests/AppConfigurationTests.swift`
- Modify: `CornerPetTests/CaptureCompositionTests.swift`
- Create: `CornerPetTests/ReminderIntegrationTests.swift`
- Modify: `CornerPetUITests/CaptureFlowUITests.swift`
- Create: `CornerPetUITests/ReminderFlowUITests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AppSettings` typed changes, `ScreenCoordinator.currentConfiguration`, `CapturePanelController.isVisible`, `CaptureComposing`, `ReminderScheduler`, and `PetReminderPanelController`.
- Produces: production startup/wake/settings wiring, Inbox-opening action, capture-before-cat conflict resolution, and gated deterministic UI-test reminder fixtures.

- [ ] **Step 1: Add failing Settings tests and UI assertions**

Assert `settings.reminderEnabled` exists, defaults on, disables the time picker when off, and the footer states that no system notification permission is used.

- [ ] **Step 2: Update Settings UI and pass focused Settings tests**

Replace the Task 11 “future version” footer with current paired copy. Keep the time picker binding and disable it when `reminderEnabled` is false.

- [ ] **Step 3: Add failing integration tests for scheduler creation and typed changes**

Assert app launch starts the scheduler after screen/capture composition exists; `.dailyReminderMinutes` and `.reminderEnabled` update it immediately; termination stops it.

- [ ] **Step 4: Add failing conflict tests**

Prove a due normal reminder with visible capture records handling and does not present the cat. Prove any capture presentation dismisses a visible cat first. Prove a pinned capture is neither moved nor unpinned.

- [ ] **Step 5: Extend `CaptureComposing` with an Inbox-selection interface**

Add:

```swift
func selectInbox()
```

The production implementation calls `shellViewModel.select(.inbox)`; default test implementations remain no-op.

- [ ] **Step 6: Wire “Open Inbox”, snooze, dismiss, screen changes, and corner changes**

Open Inbox must complete the current reminder, dismiss the cat, select Inbox, then use the existing lifecycle coordinator and capture controller on the cat's display. Snooze stores `now + 600`, dismisses the cat, and does not change global settings. Dismiss for Today completes and dismisses only.

- [ ] **Step 7: Add gated UI-test launch options for deterministic cat presentation**

Extend `AppLaunchOptions` only behind `--cornerpet-ui-testing`. Add arguments for forced reminder presentation and one of four trigger corners. Ungated arguments must have no effect in production.

- [ ] **Step 8: Add UI tests for all three actions and four-corner placement fixtures**

Assert Open Inbox reveals `capture.panel` with `inbox.list`; Snooze removes `reminder.panel`; Dismiss removes it; all four fixtures put the rail on the expected side and vertical region of the selected screen.

- [ ] **Step 9: Run focused AppSettings, integration, capture, and reminder UI suites until green**

---

### Task 6: Full Regression Verification and Self-Review

**Files:**
- Modify only files required to fix verified failures or review findings.

**Interfaces:**
- Consumes: complete Task 12 implementation.
- Produces: reproducible build/test evidence and a user-facing manual acceptance checklist.

- [ ] **Step 1: Run all Task 12 unit tests serially**

```bash
xcodebuild test -project CornerPet.xcodeproj -scheme CornerPet -destination 'platform=macOS,arch=arm64' -only-testing:CornerPetTests/ReminderPolicyTests -only-testing:CornerPetTests/ReminderStateStoreTests -only-testing:CornerPetTests/ReminderSchedulerTests -only-testing:CornerPetTests/PetReminderPositionerTests -only-testing:CornerPetTests/PetReminderPanelControllerTests -only-testing:CornerPetTests/ReminderIntegrationTests
```

- [ ] **Step 2: Run the complete CornerPet unit test suite**

```bash
xcodebuild test -project CornerPet.xcodeproj -scheme CornerPet -destination 'platform=macOS,arch=arm64' -only-testing:CornerPetTests
```

- [ ] **Step 3: Run every UI test**

```bash
xcodebuild test -project CornerPet.xcodeproj -scheme CornerPet -destination 'platform=macOS,arch=arm64' -only-testing:CornerPetUITests
```

- [ ] **Step 4: Build arm64 Debug and confirm `BUILD SUCCEEDED`**

```bash
xcodebuild build -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug -destination 'platform=macOS,arch=arm64'
```

- [ ] **Step 5: Run static diff checks**

```bash
git diff --check
git status --short
rg -n 'UNUserNotification|Input Monitoring|CGEventTap|NSEvent\.addGlobalMonitor' CornerPet
```

Expected: no whitespace errors, only Task 12-scoped files are changed, and no prohibited notification or input-monitoring implementation was added.

- [ ] **Step 6: Self-review correctness, regressions, privacy, performance, accessibility, and maintainability**

Inspect every changed hunk. Fix accepted findings and rerun the narrowest affected tests, then repeat full unit tests, all UI tests, and arm64 Debug build.

- [ ] **Step 7: Provide Jack with exact test counts, build result, changed-file summary, remaining manual sleep/DST/multi-display checks, and no Git commit**

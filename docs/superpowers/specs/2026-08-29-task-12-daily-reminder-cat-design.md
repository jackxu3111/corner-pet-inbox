# Task 12 Daily Reminder and Cat Design

## Status and Constraints

Jack approved this design in chat on 2026-08-29. Implementation must remain in the Codex-managed worktree at `/Users/jack/.codex/worktrees/ce75/CornerPet`, based on verified commit `c3b7f1e`. Do not write to `/Users/jack/MyApp/CornerPet`. Do not commit, push, merge, reset, or discard changes without Jack's explicit authorization.

CornerPet remains a macOS 14+, Apple Silicon-only, Swift 6 accessory application. It must not add system notification permission, Input Monitoring, a global keyboard shortcut, a Dock icon, a menu-bar item, third-party dependencies, or external cat assets. Existing hidden startup, four-corner triggering, multi-display behavior, full-screen access, pinning, drafts, editing, archive, favorites, and capture-panel lifecycle must remain intact.

Task 13's complete localization and accessibility pass remains deferred. Task 12 keeps the current Chinese/English paired-copy convention and adds only the identifiers and reduced-motion behavior necessary for the new reminder flow.

## Scope Classification

Task 12 is architectural because it introduces a persistent reminder state, a pure scheduling policy, a lifecycle-aware scheduler, and a second AppKit panel whose behavior must remain independent from the existing capture-panel state machine.

## Confirmed Product Decisions

- Daily reminders are enabled by default.
- If the capture panel is visible, opening, closing, returning, or pinned when a normal reminder is due, that day's reminder is considered handled without displaying the cat.
- The cat appears on the display containing the mouse pointer and falls back to the primary display when no display contains the pointer.
- The cat uses the configured trigger corner: left corners use a left edge rail, right corners use a right edge rail, top corners align near the top, and bottom corners align near the bottom.
- The cat rail leaves the existing 86-point hot-corner region clear.
- “Dismiss for Today” dismisses only the current day's reminder; the Settings toggle is the only global enable/disable control.

## Settings and Persistent State

Extend `AppSettings` with `reminderEnabled`, defaulting to `true`, persisted under `CornerPet.reminderEnabled`, included in `AppSettingsSnapshot`, and published through a new `.reminderEnabled` field.

Persist runtime reminder state in `UserDefaults`:

| Field | Key | Meaning |
| --- | --- | --- |
| `lastFiredAt` | `CornerPet.reminder.lastFiredAt` | Absolute time at which the current local day's normal reminder was handled |
| `snoozedUntil` | `CornerPet.reminder.snoozedUntil` | Absolute deadline for the next ten-minute follow-up, or absent |

Normal reminder state is written before any presentation callback. A due snooze is cleared before presentation. These orderings prefer no repeated harassment after a crash over retrying a panel presentation that may have failed.

Disabling reminders immediately clears `snoozedUntil`, hides an existing cat panel, and stops minute-based evaluation until reminders are enabled again. Re-enabling after today's scheduled time fires immediately only when today's normal reminder has not already been handled.

## Pure Reminder Policy

`ReminderPolicy` is a value-type module with no timers, notifications, AppKit dependencies, or persistence side effects. It accepts:

- current absolute time;
- `reminderEnabled` and `dailyReminderMinutes`;
- persisted `lastFiredAt` and `snoozedUntil`;
- an injected `Calendar` representing the current autoupdating system calendar;
- whether the capture panel and cat panel are visible.

It returns a `ReminderDecision` that describes both the requested presentation and the state mutation the scheduler must persist first. Decisions are:

- `.none`;
- `.clearSnooze`;
- `.handleNormalWithoutPresentation(firedAt:)`;
- `.presentNormal(firedAt:)`;
- `.presentSnoozed(clearSnooze: true)`.

Policy order is deterministic:

1. Disabled reminders clear an outstanding snooze and otherwise do nothing.
2. A visible cat prevents duplicate presentation.
3. A due snooze takes precedence over the daily normal reminder.
4. If a due snooze finds the capture panel visible, it is consumed without presentation.
5. A normal reminder is due only after today's scheduled instant and only when `lastFiredAt` is not in today's local calendar day.
6. A due normal reminder with a visible capture panel is marked handled without presentation.
7. Otherwise the due normal reminder is presented.

“Ten minutes later” stores `now + 600 seconds`, may be chosen repeatedly, and may cross midnight. Opening the inbox or dismissing for today clears the outstanding snooze.

## Calendar, Time Zone, and DST Semantics

Every evaluation receives a fresh `Calendar.autoupdatingCurrent`; the scheduler does not cache a fixed time zone.

Today's configured time is calculated with `date(bySettingHour:minute:second:of:matchingPolicy:repeatedTimePolicy:direction:)` using `.nextTime`, `.first`, and `.forward`:

- During a spring-forward gap, a nonexistent local time fires at the next valid time on the nominal day.
- During a fall-back repeat, the first matching time is chosen and same-local-day suppression prevents a second normal reminder.
- Days are recalculated through the calendar; no behavior assumes a day is exactly 86,400 seconds.
- After a time-zone change, “today” and today's scheduled instant are reinterpreted in the new current time zone.

## Scheduler and Lifecycle

`ReminderScheduler` is a main-actor module with this external interface:

- `start(configuration:)`;
- `update(configuration:)`;
- `evaluate(reason:)`;
- `snooze()`;
- `completeCurrentReminder()`;
- `stop()`.

It owns the reminder state store, one main-run-loop minute timer, and notification observers. It evaluates:

- immediately at app launch;
- once per minute while enabled;
- when `NSWorkspace.didWakeNotification` arrives through `NSWorkspace.shared.notificationCenter`;
- when the default notification center reports calendar-day, system-clock, or system-time-zone changes;
- immediately when the reminder enabled state or daily time changes.

The scheduler injects clock, calendar, timer scheduling, notification centers, capture visibility, cat visibility, and presentation callbacks so policy and lifecycle behavior are deterministic in tests. `stop()` invalidates the timer and removes every observer.

## Cat Reminder Edge Rail

`PetReminderPanelController` owns at most one borderless, nonactivating `NSPanel` and hosts `CatReminderView`. The panel does not enter `PanelStateMachine` and does not mutate capture draft, edit, pin, position, or navigation state.

The initial rail size is 240×300 points. Positioning uses current `ScreenConfiguration.allScreens`, `NSEvent.mouseLocation`, and the configured `TriggerCorner`:

- choose the screen containing the pointer;
- otherwise choose the primary screen, then the first available screen;
- attach to the selected screen's left or right visible edge;
- align near its top or bottom while keeping the 86-point trigger region clear;
- clamp the final frame to the visible frame;
- relocate the visible rail after screen configuration or corner changes.

`CatReminderView` draws one original cat using SwiftUI `Circle`, `Capsule`, `RoundedRectangle`, and `Path` primitives. It provides three bilingual buttons:

- `打开收件箱 / Open Inbox`;
- `10 分钟后提醒 / Remind in 10 Minutes`;
- `关闭 / 今天不再提醒 / Dismiss for Today`.

The normal entrance is a short edge-peek and paw motion. Reduce Motion uses opacity only. The panel is shown without taking keyboard focus from the user's current application.

## Capture-Panel Conflict Behavior

- A due reminder never displays a cat when `CapturePanelController.isVisible` is true; it records the normal reminder as handled or consumes a due snooze.
- Any capture presentation request while the cat is visible dismisses the cat before the existing capture lifecycle continues.
- “Open Inbox” dismisses the cat, clears snooze, selects `.inbox`, and presents the one existing capture panel on the cat's screen. If a race has already made capture visible, it preserves the panel's frame and pin state, selects Inbox, and brings it forward.
- The cat edge rail leaves the hot-corner geometry clear, so it does not replace, resize, or add trigger zones.
- Settings may coexist with the cat. Only the capture panel counts as handling the reminder.

## Settings UI

Update the Daily Reminder section to contain:

- an enabled toggle with identifier `settings.reminderEnabled`;
- the existing time picker, disabled when reminders are off;
- paired copy explaining that reminders use an in-app cat edge rail and require no system notification permission.

The scheduler receives changes through the existing typed `AppSettings.onChange` route. Other settings and launch-at-login behavior are unchanged.

## Testing and Acceptance

Pure policy tests cover before/at/after schedule, launch catch-up, default enabled, disabled behavior, same-day suppression, capture-visible consumption, cat-visible deduplication, ten-minute snooze, repeated snooze, midnight crossing, and wake-after-schedule decisions.

Calendar tests use fixed Gregorian calendars and time zones to cover time changes, time-zone reinterpretation, spring-forward nonexistent time, and fall-back repeated time.

Scheduler tests prove evaluation triggers, observer and timer cleanup, configuration updates, persistence-before-presentation, due-snooze clearing, repeated wake suppression, disabling behavior, and callback routing.

Panel and positioning tests cover four configured corners, current-pointer display selection, primary fallback, trigger-zone clearance, screen disconnect relocation, singleton presentation, and no focus activation. UI tests cover all three actions and the Settings toggle/time relationship.

Final verification requires:

- focused Task 12 unit and UI tests;
- all CornerPet unit tests;
- all CornerPet UI tests;
- arm64 Debug build;
- `git diff --check` and a review of changed files;
- self-review for correctness, regressions, privacy, performance, accessibility, and maintainability.

No Git commit, push, or merge is allowed before Jack's explicit acceptance.

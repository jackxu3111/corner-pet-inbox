# Task 11 Settings, Displays, and Login Launch Design

## Status and Constraints

Jack approved this design in chat on 2026-08-28. The implementation must remain in the isolated CornerPet worktree based at commit `e78633b`. Do not commit, push, reset, or discard changes without Jack's explicit authorization.

CornerPet remains a macOS 14+, Apple Silicon-only, Swift 6 accessory application. Existing capture, draft, item lifecycle, pinning, animation, full-screen, and corner-return behavior must remain intact.

## Scope Classification

Task 11 is architectural because it introduces a shared settings module, a native settings scene, a multi-display runtime, a ServiceManagement adapter, and launch-behavior wiring that changes interfaces between the app composition root, trigger coordinator, and panel controller.

## Current-State Findings

- `TriggerCornerStore` persists the corner under `CornerPet.triggerCorner`.
- `PinnedPanelSizeStore` persists the last pinned size under `com.jack.cornerpet.pinnedPanelSize`.
- The accepted current default panel size is 360×450 points in production code and tests.
- Dwell is fixed at 0.4 seconds through `DwellTiming.duration`.
- `CornerTriggerCoordinator` currently owns exactly two trigger panels for one `NSScreen.main` screen.
- There is no display-scope setting, screen-parameter observer, all-display trigger runtime, or disconnected-display fallback.
- The SwiftUI `Settings` scene contains `EmptyView`, while the capture panel shows a Settings placeholder.
- `LSUIElement=YES` and accessory activation mean CornerPet has no app menu bar.
- Production launch already creates no visible window; only gated UI-test arguments open capture.

## Settings Model and Persistence

Create one main-actor observable `AppSettings` runtime model with these fields:

| Field | Default | Persistence |
| --- | --- | --- |
| `triggerCorner` | `.topLeft` | existing `CornerPet.triggerCorner` key |
| `displayScope` | `.primary` | `CornerPet.displayScope` |
| `lastPinnedSize` | 360×450 | existing `com.jack.cornerpet.pinnedPanelSize` key |
| `dailyReminderMinutes` | 540 (09:00) | `CornerPet.dailyReminderMinutes` |
| `language` | `.system` | `CornerPet.language` |

`TriggerCornerStore` and `PinnedPanelSizeStore` remain persistence-format adapters used behind `AppSettings`; the running app must not maintain independent in-memory setting owners. Existing keys are adopted in place rather than copied into a new settings blob.

Invalid raw enum values fall back to their defaults. Reminder minutes outside `0...1439` fall back to 540. Size validation retains the current `PinnedPanelSizeStore` finite-value and clamping rules.

`AppSettings` publishes a typed change containing the changed field and a complete snapshot after validation and persistence. Runtime consumers receive changes immediately. Dwell remains the read-only `DwellTiming.duration` constant and is neither persisted nor exposed as a setting.

## Settings Change Data Flow

```text
Settings UI or panel resize/return
    → AppSettings validates and persists
    → AppSettings publishes SettingsChange(field, snapshot)
    → AppDelegate routes the change
        → corner/scope reconfigure the screen and trigger runtime
        → corner updates the panel controller's future placement
        → size is used on the next presentation
        → reminder and language are published for later tasks only
```

Panel return-to-corner writes through `AppSettings`, preserving Task 10's immediate hot-zone refresh. Panel live-resize completion also writes through `AppSettings`, avoiding a second runtime source.

## Minimal Multi-Display Runtime

Add a `ScreenCoordinator` module with a small interface: `start(scope:)`, `updateScope(_:)`, `stop()`, and `onChange`. It owns screen enumeration, primary-display selection using `CGMainDisplayID()`, conversion to stable screen snapshots, display-scope filtering, and observation of `NSApplication.didChangeScreenParametersNotification`.

`CornerTriggerCoordinator` consumes enabled screen snapshots and owns one horizontal/vertical trigger-panel pair per enabled display. It retains one shared dwell state and reports the actual triggering display ID. Reconfiguration cancels pending dwell, removes stale panels, rebuilds frames, and refreshes pointer presence atomically.

Behavior:

- Primary scope exposes trigger zones only on the system primary display.
- All scope exposes the same configured corner on every connected display.
- Only one capture panel exists.
- An unpinned panel opens on the triggering display.
- A trigger while an existing panel is pinned brings that panel forward without moving or duplicating it.
- Connecting, disconnecting, rearranging, or scaling displays rebuilds trigger geometry immediately.
- If the current panel display disappears, `CapturePanelController` moves the panel inside the primary display's visible frame while preserving size and pinned state when possible.
- Per-display corner preferences are not supported.

## Native Settings Window and Entry

Replace the empty SwiftUI `Settings` scene with a native `SettingsView` containing:

- Corner picker with four corners.
- Display scope picker for Primary Display and All Displays.
- Read-only text stating that dwell is fixed at 0.4 seconds.
- Hour-and-minute reminder-time picker.
- Language picker for Follow System, Simplified Chinese, and English.
- Launch-at-login system status and control.
- Hot-corner conflict help.

The capture panel's Settings navigation item becomes a `SettingsLink`. It opens the independent singleton settings scene instead of selecting the old placeholder. It has the standard Command-comma shortcut while the capture panel is key. CornerPet does not add a Dock icon, `MenuBarExtra`, or global shortcut.

Opening Settings may cause the capture panel to follow its existing external-focus-loss behavior. Closing Settings does not terminate the accessory app or stop its hot zones.

The reminder-time UI states that scheduling is not active in this build and that the preference is only being saved. The language UI states that existing screens may remain bilingual. Task 11 does not add `reminderEnabled`; scheduling and disabling behavior belong to Task 12.

## Login Item Module

Define a `LoginItemManaging` seam with `status`, `register()`, `unregister()`, and `openSystemSettings()`. The production adapter wraps `SMAppService.mainApp`; tests use a fake adapter.

Expose all real ServiceManagement states:

- `notRegistered`: off.
- `enabled`: on.
- `requiresApproval`: show guidance and use `SMAppService.openSystemSettingsLoginItems()`.
- `notFound`: show an unavailable/configuration failure state.

Registration and unregistration errors appear inline. After every operation, success or failure, the controller re-reads the system status. No launch-at-login Boolean is stored in `UserDefaults`.

The controller refreshes when the settings view appears and when CornerPet becomes active again after the user visits System Settings.

## Hidden Login Launch

`SMAppService.mainApp` starts the same production executable. Production startup always initializes storage, the screen runtime, and hot zones without opening capture or settings. No private launch-source detection is introduced. UI-test-only launch behavior remains gated behind `--cornerpet-ui-testing`.

## Conflict Help Copy and Privacy

Show conflict help directly in Settings without requiring a disclosure or secondary sheet. Do not attempt conflict detection.

Chinese:

> CornerPet 无法检测 macOS 触发角是否冲突。若同一角落已分配系统操作，两者可能同时响应。请前往“系统设置 → 桌面与程序坞 → 触发角…”，清除该角落的系统操作，或在 CornerPet 中选择其他角落。CornerPet 不会读取或更改这些系统设置。

English:

> CornerPet can’t detect whether macOS Hot Corners conflict with this setting. Go to “System Settings → Desktop & Dock → Hot Corners…” to clear the system action, or choose another CornerPet corner. CornerPet never reads or changes these system settings.

Do not read or write private Dock preferences, use private settings URLs, or add Input Monitoring.

## Non-Goals

- Reminder scheduling, notifications, sleep recovery, snooze, or cat UI.
- Full localization or applying the language preference to every screen.
- Variable dwell presets.
- Per-display corners.
- Menu-bar presence, Dock presence, or global keyboard shortcuts.
- Automatic Hot Corners conflict detection or mutation.
- Broad capture-panel redesign.

## Verification and Acceptance

Automated coverage must prove:

- AppSettings defaults, persistence, invalid-value fallback, and old-key adoption.
- 360×450 remains the accepted default.
- Typed settings changes publish immediately.
- Corner and scope changes update runtime trigger zones immediately.
- Primary scope creates one trigger pair and all scope creates one pair per display.
- The correct display ID is used to present the single panel.
- Display change removes stale zones and disconnected panels return to the primary visible area.
- Login item status, registration, unregistration, approval, not-found, and failure behavior use system truth.
- Production/login-style launch opens no window and still starts hot zones.
- Settings replaces the old capture placeholder.
- Dwell remains exactly 0.4 seconds.

After focused tests pass, run the complete serial CornerPetTests suite (271-test baseline plus additions), an arm64 Debug build, real Settings and login-item manual checks, and an independent GPT-5.6 Sol high review. Fix review findings and rerun verification before handing the build to Jack.

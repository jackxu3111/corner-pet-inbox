# Task 11 Settings, Displays, and Login Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver persistent native settings, a real primary/all-display hot-corner runtime, public conflict help, and system-truth launch-at-login behavior while preserving all accepted CornerPet interactions.

**Architecture:** `AppSettings` owns runtime preferences while existing corner and size stores remain in-place persistence adapters. `ScreenCoordinator` publishes enabled display snapshots; `CornerTriggerCoordinator` owns per-display trigger zones; `LoginItemController` wraps a replaceable `SMAppService.mainApp` adapter. `AppDelegate` remains the composition root and routes typed changes.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, CoreGraphics, ServiceManagement, XCTest, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-28-task-11-settings-displays-login-design.md`

## Global Constraints

- Work only in `/Users/jack/.codex/worktrees/ce76/CornerPet` at baseline `e78633b`.
- Do not commit, push, reset, or discard changes without Jack's explicit authorization.
- Keep dwell fixed at exactly 0.4 seconds.
- Preserve the existing `CornerPet.triggerCorner` and `com.jack.cornerpet.pinnedPanelSize` keys.
- Keep the accepted default panel size at exactly 360×450 points.
- Do not add Input Monitoring, private system-preference access, private settings URLs, a Dock icon, a menu-bar extra, or a global shortcut.
- Reminder scheduling and full localization remain deferred.

---

### Task 1: Unified AppSettings

**Files:**
- Create: `CornerPet/Settings/AppSettings.swift`
- Test: `CornerPetTests/AppSettingsTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TriggerCornerStore`, `PinnedPanelSizeStore`, `DwellTiming.duration`.
- Produces: `DisplayScope`, `AppLanguage`, `AppSettingsSnapshot`, `AppSettingsField`, `AppSettingsChange`, and main-actor observable `AppSettings` with validated setters and `onChange`.

- [ ] Write tests asserting top-left, primary, 360×450, 540, system, and 0.4 defaults.
- [ ] Run `AppSettingsTests` and confirm compilation fails because `AppSettings` does not exist.
- [ ] Add enums, snapshot/change values, exact new keys, old-store adapters, validated load/set methods, and immediate change publication.
- [ ] Add tests for fresh-instance persistence, invalid raw values, invalid minutes, old-key adoption, size clamping, and no duplicate corner/size key.
- [ ] Run `AppSettingsTests` and existing `TriggerCornerStoreTests` plus `PinnedPanelSizeStoreTests` until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 2: ScreenCoordinator and Dynamic Display Scope

**Files:**
- Create: `CornerPet/Screen/ScreenCoordinator.swift`
- Test: `CornerPetTests/ScreenCoordinatorTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DisplayScope`, injected `[ScreenSnapshot]` provider, injected primary display ID provider, and injected notification center.
- Produces: `ScreenSnapshot`, `ScreenConfiguration`, `ScreenCoordinator.start(scope:)`, `updateScope(_:)`, `stop()`, and `onChange`.

- [ ] Write tests for primary filtering, all-display ordering, missing-primary fallback, scope updates, display-change notifications, and stop removing observation.
- [ ] Run `ScreenCoordinatorTests` and confirm expected missing-type failures.
- [ ] Implement stable display snapshots, `CGMainDisplayID()` selection, notification observation, and deduplicated change publication.
- [ ] Run `ScreenCoordinatorTests` until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 3: Multi-Display Trigger Runtime

**Files:**
- Modify: `CornerPet/HotCorner/CornerTriggerCoordinator.swift`
- Modify: `CornerPet/HotCorner/TriggerZonePanel.swift`
- Test: `CornerPetTests/CornerTriggerCoordinatorTests.swift`
- Test: `CornerPetTests/TriggerZonePanelTests.swift`

**Interfaces:**
- Consumes: `ScreenConfiguration`, shared fixed dwell state, pointer provider, and panel lifecycle callbacks.
- Produces: `updateScreens(_:)`, `updateConfiguration(corner:screens:)`, per-display trigger-panel pairs, and actual triggering display IDs.

- [ ] Add failing tests proving primary creates one pair, all displays create one pair per screen, a secondary dwell presents its ID, corner/scope updates cancel dwell, and stale panels disappear.
- [ ] Run focused trigger tests and capture the expected failures.
- [ ] Replace the single-screen/frame storage with deterministic per-display zone storage and active-trigger display tracking while preserving existing lifecycle/reversal semantics.
- [ ] Add a pinned-visible retrigger path that calls a bring-forward intent without creating or moving another panel.
- [ ] Run all hot-corner and trigger-zone tests until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 4: Panel Settings Integration and Display Fallback

**Files:**
- Modify: `CornerPet/Panel/CapturePanelController.swift`
- Modify: `CornerPet/Panel/PanelPositioner.swift`
- Modify: `CornerPet/Panel/PinnedPanelSizeStore.swift`
- Test: `CornerPetTests/PanelAnimatorTests.swift`
- Test: `CornerPetTests/PanelPositionerTests.swift`

**Interfaces:**
- Consumes: `AppSettings` size adapter, corner updates, and `ScreenConfiguration` changes.
- Produces: `updateCorner(_:)`, `handleScreenConfigurationChange(_:)`, `bringForward()`, and a frame-clamping positioner operation.

- [ ] Add failing tests for future placement after corner change, resize writing through unified settings, pinned disconnected-screen fallback, unpinned fallback, rearranged visible-frame clamping, and bring-forward without movement.
- [ ] Run the focused panel tests and capture expected failures.
- [ ] Implement injected size load/save closures, corner updates, visible-frame clamping, display-disconnect recovery, and bring-forward behavior without changing pin state.
- [ ] Run all panel animator/positioner tests until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 5: Real Login Item State Machine

**Files:**
- Create: `CornerPet/Settings/LoginItemController.swift`
- Test: `CornerPetTests/LoginItemControllerTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SMAppService.mainApp` through `LoginItemManaging`.
- Produces: `LoginItemStatus`, observable `LoginItemController`, `refresh()`, `setEnabled(_:)`, and `openApprovalSettings()`.

- [ ] Write fake-adapter tests for not-registered, enabled, requires-approval, not-found, successful register/unregister, register/unregister failure, and always-refresh-after-operation.
- [ ] Run `LoginItemControllerTests` and confirm missing-type failures.
- [ ] Implement the protocol, production SMAppService adapter, typed UI status, inline error state, and approval-settings action.
- [ ] Run `LoginItemControllerTests` until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 6: Native Settings Scene and Honest Help

**Files:**
- Create: `CornerPet/Settings/SettingsView.swift`
- Modify: `CornerPet/App/CornerPetApp.swift`
- Modify: `CornerPet/Capture/CaptureNavigationBar.swift`
- Modify: `CornerPet/Capture/CapturePanelView.swift`
- Modify: `CornerPet/Capture/CaptureDestination.swift`
- Modify: `CornerPetUITests/CaptureFlowUITests.swift`
- Create: `CornerPetUITests/SettingsFlowUITests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: observable `AppSettings`, observable `LoginItemController`, SwiftUI `Settings`, and `SettingsLink`.
- Produces: the native settings window, capture-panel Settings entry, Command-comma shortcut, and always-visible conflict-help section.

- [ ] Replace the old placeholder UI test with a failing test that expects a settings window and real controls.
- [ ] Add UI-test assertions for corner, display scope, reminder time, language, login status, always-visible conflict-help copy, and Command-comma from the capture panel.
- [ ] Run focused UI tests and capture expected failures.
- [ ] Implement the Settings form, honest reminder/language footers, exact public conflict-help copy, SettingsLink navigation, and accessibility identifiers.
- [ ] Run focused Settings and capture-navigation UI tests until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 7: Composition, Immediate Runtime Updates, and Hidden Launch

**Files:**
- Modify: `CornerPet/App/AppDelegate.swift`
- Modify: `CornerPet/App/CornerPetApp.swift`
- Modify: `CornerPetTests/AppConfigurationTests.swift`
- Modify: `CornerPetTests/CaptureCompositionTests.swift`
- Modify: `CornerPetUITests/CornerPetLaunchTests.swift`

**Interfaces:**
- Consumes: `AppSettings`, `ScreenCoordinator`, multi-screen `CornerTriggerCoordinator`, `CapturePanelController`, and `LoginItemController`.
- Produces: one composition root that starts hidden, routes settings changes immediately, starts/stops screen observation, and exposes settings dependencies to the SwiftUI scene.

- [ ] Add failing integration tests for corner/scope immediate updates, panel-originated corner updates, screen notifications reaching trigger and panel modules, login-style production launch remaining hidden, and hot zones still starting.
- [ ] Run the focused integration tests and capture expected failures.
- [ ] Rewire AppDelegate factories and callbacks around the unified modules without opening production windows.
- [ ] Update test factories to inject deterministic settings/screens/login adapters.
- [ ] Run AppConfigurationTests, CaptureCompositionTests, and CornerPetLaunchTests until they pass.
- [ ] Inspect `git diff` and leave changes uncommitted.

### Task 8: Regression Verification, Manual Checks, and Independent Review

**Files:**
- Modify only files required to fix verified regressions or review findings.

**Interfaces:**
- Consumes: completed Task 11 implementation.
- Produces: reproducible verification evidence and a user-facing local acceptance checklist.

- [ ] Run all Task 11-focused unit tests serially.
- [ ] Run the full serial CornerPetTests suite using Xcode 27 beta and confirm the 271 baseline plus additions passes.
- [ ] Build the CornerPet arm64 Debug application and confirm `BUILD SUCCEEDED`.
- [ ] Launch the signed Debug app and manually verify the settings window, corner switching, display scope, conflict help, login-item register/status/unregister, and background-hidden behavior.
- [ ] Confirm no Input Monitoring prompt, private preference access, unexpected Dock icon, capture popup, or duplicate panel occurs.
- [ ] Request one independent GPT-5.6 Sol high code review covering correctness, regressions, security/privacy, and maintainability.
- [ ] Fix every accepted finding and rerun focused tests, full serial tests, and arm64 Debug build.
- [ ] Recheck `git status`, summarize every changed file, and provide Jack with exact Task 11 local acceptance steps without committing.

# Atoll-style Corner Trigger Design

**Date:** 2026-08-26
**Status:** Approved direction for implementation planning
**Scope:** Main-screen, top-left trigger demonstration only

## 1. Outcome

CornerPet will open its capture panel after the pointer remains for 400 ms inside a top-left L-shaped trigger composed of an 86×20 pt horizontal arm and a 20×86 pt vertical arm. The trigger uses transparent, always-on-top, nonactivating `NSPanel` windows and `NSTrackingArea` enter/exit events. It does not install local or global mouse-moved event monitors and does not request Input Monitoring permission.

Once the capture panel is visible, the union of both trigger arms and the capture panel is the keep-open region. Leaving that union starts a 100 ms close debounce. At expiry, the adapter samples `NSEvent.mouseLocation`; it closes only if the pointer is still outside. Re-entry cancels the pending close. Escape closes immediately.

This design borrows only Atoll's observable architectural principle—using owned AppKit surfaces and tracking-area boundary events instead of continuously monitoring global pointer movement. No Atoll source, identifiers, control flow, or implementation text may be copied or translated. Atoll is GPL-3.0, while this design is a clean-room implementation from the behavior described above and Apple's public APIs. See [Atoll's repository and license](https://github.com/Ebullioscopic/Atoll).

## 2. Current Repository Baseline

The implementation worker must begin by preserving the current dirty worktree. At planning time, branch `codex/cornerpet-task-4luna` contains:

- Modified: `CornerPet.xcodeproj/project.pbxproj`
- Modified: `CornerPet/App/AppDelegate.swift`
- Modified: `CornerPet/HotCorner/HotCornerGeometry.swift`
- Modified: `CornerPetTests/AppConfigurationTests.swift`
- Modified: `CornerPetTests/HotCornerGeometryTests.swift`
- Untracked: `CornerPet/App/InputMonitoringPermissionCoordinator.swift`
- Untracked: `CornerPet/Panel/CapturePanelController.swift`
- Untracked: `CornerPet/Panel/CornerPanel.swift`
- Untracked: `CornerPet/Panel/PanelAnimator.swift`
- Untracked: `CornerPet/Panel/PanelPositioner.swift`
- Untracked: `CornerPetTests/PanelAnimatorTests.swift`
- Untracked: `CornerPetTests/PanelPositionerTests.swift`

The dirty `project.pbxproj` also contains the user's signing team and the newly added Panel group/file references. Those changes are user-owned and must not be regenerated or overwritten.

Baseline verification on 2026-08-26:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests test
```

Result: `TEST SUCCEEDED`; all current unit tests passed. Running the full scheme built and ran the unit suite, but the UI-test operation did not finish within the observation window and was interrupted. This is a baseline harness issue to recheck after the permission launch path is removed, not evidence of a unit-test failure.

The shell's default developer directory is Command Line Tools. Commands in this spec use a one-command `DEVELOPER_DIR` override and do not change global `xcode-select` state.

## 3. Goals

1. Require no Input Monitoring permission for the corner trigger demonstration.
2. Detect pointer boundary entry and exit through `NSTrackingArea` configured with `.mouseEnteredAndExited`, `.activeAlways`, and `.inVisibleRect`.
3. Use two exact trigger panels on `NSScreen.main.frame`:
   - Horizontal: 86×20 pt, touching `frame.minX` and `frame.maxY`.
   - Vertical: 20×86 pt, touching `frame.minX` and `frame.maxY`.
4. Preserve one dwell start while moving anywhere inside the union of both arms.
5. Open exactly once after 400 ms, after a deadline-time pointer recheck.
6. Treat trigger arms plus visible capture panel as one keep-open region.
7. Close only after 100 ms continuously outside that union and a deadline-time pointer recheck.
8. Cancel pending close on re-entry; reverse an already-started close if the existing animation supports it safely.
9. Close on Escape without a global keyboard monitor.
10. Make trigger and capture panels work in fullscreen auxiliary spaces, with the main screen as the required demonstration target.
11. Keep time and pointer sampling injectable; keep transition logic pure and deterministic.

## 4. Non-goals

- Item, task, draft, or note persistence.
- Capture content UI beyond the existing probe view.
- Multiple displays, selectable corners, or dynamic display hot-plug behavior.
- Accessibility, Input Monitoring, or Screen Recording permission flows.
- A continuous pointer-position poller.
- Copying or adapting GPL code from Atoll.
- Changing animation timing or panel placement except where needed for the new keep-open lifecycle.

## 5. Considered Approaches

### A. Tracking panels plus pure interaction state machine — selected

Create one transparent nonactivating panel per trigger arm. Each panel owns a tracking view. Boundary callbacks cause a coordinator to sample the injected pointer provider, calculate membership in the union, and feed a pure state machine. The state machine emits presentation, dismissal, reversal, and deadline scheduling effects.

This is event-driven, permission-free, testable, and matches the requested Atoll-style principle.

### B. Periodic `NSEvent.mouseLocation` polling — rejected

A timer could poll the pointer without installing a global mouse-moved monitor. It would avoid Input Monitoring but consume work continuously, introduce sampling gaps, and weaken the explicit requirement to use tracking-area enter/exit events. Pointer sampling remains appropriate only for boundary reconciliation and deadline verification.

### C. Local/global `NSEvent` mouse-moved monitors — rejected

The existing `MouseMonitor` registers both local and global `.mouseMoved` monitors. This couples the feature to Input Monitoring behavior and is explicitly outside the requested architecture. Both registrations and their permission coordinator must be removed.

## 6. Recommended Architecture

```text
TriggerZonePanel (horizontal) ─┐
                              ├─ boundary callback ─┐
TriggerZonePanel (vertical) ───┘                    │
CapturePanel tracking view ─────────────────────────┤
                                                   v
                                      CornerTriggerCoordinator
                                      - injected monotonic clock
                                      - injected pointer provider
                                      - injected deadline scheduler
                                      - geometry/panel-frame membership
                                                   │
                                                   v
                                      HotCornerStateMachine (pure)
                                      state + event -> [effect]
                                                   │
                          ┌────────────────────────┼─────────────────────┐
                          v                        v                     v
                     present panel           dismiss/reverse       schedule/cancel
```

### 6.1 `HotCornerStateMachine`

`CornerPet/HotCorner/HotCornerStateMachine.swift` becomes a UI-free transition reducer. It receives already-reconciled pointer membership and monotonic timestamps. It must not import AppKit, call `NSEvent`, create `Timer`/`Task`, or invoke a controller.

Recommended public-to-module model:

```swift
struct HotCornerPointerPresence: Equatable {
    let isInsideTrigger: Bool
    let isInsidePanel: Bool

    var isInsideKeepOpen: Bool { isInsideTrigger || isInsidePanel }
}

struct HotCornerDeadline: Equatable {
    enum Kind: Equatable { case dwell, closeDebounce }
    let kind: Kind
    let generation: Int
    let dueAt: TimeInterval
}

enum HotCornerEvent: Equatable {
    case presenceChanged(HotCornerPointerPresence, at: TimeInterval)
    case deadlineReached(HotCornerDeadline, presence: HotCornerPointerPresence, at: TimeInterval)
    case panelBeganOpening(at: TimeInterval)
    case panelDidOpen(at: TimeInterval)
    case panelBeganClosing(at: TimeInterval)
    case panelDidClose(at: TimeInterval)
    case escapePressed(at: TimeInterval)
}

enum HotCornerEffect: Equatable {
    case schedule(HotCornerDeadline)
    case cancelDeadline(HotCornerDeadline.Kind)
    case present
    case dismiss
    case reverseClosing
}
```

The deadline generation prevents a cancelled timer that races with re-entry from acting on newer state. Only the exact current deadline token is accepted.

Recommended states:

| State | Meaning |
|---|---|
| `idle` | Panel hidden, no valid dwell |
| `dwelling(startedAt:deadline:)` | Pointer is in the trigger union and the original entry time is preserved |
| `opening` | Presentation requested/animation opening |
| `open` | Capture panel visible and keep-open membership active |
| `closePending(deadline:)` | Pointer left all keep-open surfaces; 100 ms recheck pending |
| `closing` | Dismiss animation began |
| `suppressedUntilTriggerExit` | An explicit Escape/close completed while still over the trigger; prevents immediate reopen loops |

Key invariants:

- Dwell starts only on an outside-to-trigger transition while hidden.
- Any boundary callback is reconciled against the union before the event reaches the state machine. Moving between arms therefore remains `isInsideTrigger == true` and does not replace `startedAt`.
- Dwell expiry produces `.present` only when the exact deadline token matches and the deadline-time presence still reports `isInsideTrigger == true`.
- Leaving the trigger before presentation cancels dwell immediately.
- While open/opening, any presence inside either arm or the capture panel cancels close.
- Outside presence while open produces one close deadline at `now + 0.100`.
- Close expiry produces `.dismiss` only when the exact token matches and deadline-time presence is still outside.
- Escape produces `.dismiss` immediately and cancels both deadline kinds.
- A presence change inside keep-open while `closing` produces at most one `.reverseClosing` effect.
- Non-finite or backwards timestamps do not present or dismiss; they cancel only timing-dependent transient state, never corrupt a stable open/closed state.

### 6.2 `CornerTriggerCoordinator`

`CornerPet/HotCorner/CornerTriggerCoordinator.swift` is the only imperative adapter. It owns the two trigger panels, deadline cancellations, the state machine, and these injected dependencies:

```swift
typealias HotCornerClock = @MainActor () -> TimeInterval
typealias PointerLocationProvider = @MainActor () -> CGPoint

protocol HotCornerDeadlineScheduling: AnyObject {
    @MainActor
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> HotCornerCancellation
}

protocol HotCornerCancellation: AnyObject {
    func cancel()
}
```

Production dependencies use `ProcessInfo.processInfo.systemUptime`, `NSEvent.mouseLocation`, and a main-run-loop timer/task scheduler. Tests use a manual clock, a mutable point, and a scheduler whose pending operation fires only when the test requests it.

Every trigger/panel boundary callback calls `refreshPresence()`. It computes:

```swift
let point = pointerLocationProvider()
let inTrigger = HotCornerGeometry.contains(
    point: point,
    frame: mainScreen.frame,
    corner: .topLeft
)
let inPanel = panelController.keepOpenFrame?.contains(point) == true
```

This union recheck is crucial. Tracking callbacks from overlapping sibling trigger windows can arrive in either order; the coordinator must never treat an individual arm's `mouseExited` as proof that the pointer left the L shape.

At any deadline, the coordinator samples the pointer again and sends the exact deadline token plus current presence to the state machine. It must not synthesize periodic pointer events.

### 6.3 `TriggerZonePanel` and tracking view

`CornerPet/HotCorner/TriggerZonePanel.swift` contains the transparent panel and its small tracking view. Each instance has one exact arm frame.

Required panel configuration:

```swift
styleMask = [.borderless, .nonactivatingPanel]
isOpaque = false
backgroundColor = .clear
hasShadow = false
level = .statusBar
hidesOnDeactivate = false
isReleasedWhenClosed = false
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
```

Required tracking configuration:

```swift
NSTrackingArea(
    rect: .zero,
    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
    owner: self,
    userInfo: nil
)
```

Do not add `.mouseMoved`. Do not install an `NSEvent` monitor. The view forwards only `mouseEntered(with:)` and `mouseExited(with:)` to one callback.

The trigger panels necessarily participate in hit testing over their arm frames. The 86×20 horizontal arm overlaps a wider portion of the top-left menu-bar area on many Macs, so Apple-menu interference is a known demonstration risk and must be checked manually before expanding this design beyond the prototype.

### 6.4 Capture panel integration

`CornerPet/Panel/CornerPanel.swift` adds `.nonactivatingPanel` while retaining its borderless, floating, fullscreen auxiliary behavior. It remains capable of becoming key for the Escape probe, but opening it must not call `NSApp.activate()`.

`CornerPet/Panel/CapturePanelController.swift`:

- exposes a read-only `keepOpenFrame: CGRect?`, non-nil while opening/open/closing and nil when hidden;
- exposes `onPointerBoundaryChanged: (() -> Void)?` from a capture-content tracking area using the same three required options;
- keeps local Escape handling in the panel/content responder chain;
- removes the explicit application-activation closure and its test;
- retains the existing animation, lifecycle callback, focus restoration, and reversal behavior where compatible;
- does not make capture-content persistence part of this change.

The coordinator recalculates presence on capture-panel boundary changes and lifecycle changes. During animation, the controller's current presentation frame is the keep-open frame. The coordinator does not cache a stale final frame.

### 6.5 App lifecycle

`CornerPet/App/AppDelegate.swift` creates the capture controller and corner coordinator unconditionally after launch. It no longer owns or injects `InputMonitoringPermissionCoordinator`, never calls `authorize()`, and does not expose permission-gated monitoring state.

Startup order:

1. Set accessory activation policy in `applicationWillFinishLaunching`.
2. Create the capture panel controller.
3. Create the main-screen top-left coordinator with production clock/pointer/scheduler.
4. Connect panel lifecycle and boundary callbacks to the coordinator.
5. Start the coordinator, which creates/orders the two trigger panels.

Termination stops the coordinator, cancels both deadline kinds, and orders out the trigger panels. Start/stop remain idempotent.

## 7. Geometry and Coordinate Rules

Use `NSScreen.main.frame`, not `visibleFrame`, for trigger placement because the trigger must touch the physical top-left screen edge. Continue using `visibleFrame` for the existing capture-panel placement.

For main-screen frame `F`:

```swift
horizontal = CGRect(x: F.minX, y: F.maxY - 20, width: 86, height: 20)
vertical   = CGRect(x: F.minX, y: F.maxY - 86, width: 20, height: 86)
```

The 20×20 overlap is intentional. Geometry membership uses the union, including closed rectangle boundaries. Panel frames and `NSEvent.mouseLocation` are both in global AppKit screen coordinates; do not convert through a window coordinate system before membership checks.

## 8. Timing and Race Handling

- Dwell duration: exactly 0.400 seconds for this demonstration; no alternative dwell presets are retained.
- Close debounce: exactly 0.100 seconds.
- Use a monotonic time source (`systemUptime`), not wall-clock `Date`.
- Store and compare deadline tokens; cancellation alone is insufficient because a cancelled task may already be enqueued.
- A callback fired early reschedules the remaining interval or is ignored; it must not trigger an effect before `dueAt`.
- A late callback is valid only if its token is current and pointer recheck passes.
- Re-entry cancels the stored close deadline before any new action is emitted.
- A stale dwell callback after leaving cannot open the panel.
- A stale close callback after re-entry cannot close the panel.
- Individual arm entered/exited flags are not authoritative. Current pointer geometry is authoritative at reconciliation and deadline boundaries.

## 9. Permission and License Boundaries

Delete the permission coordinator and every test/reference associated with it. The final product source and tests must contain no calls to:

- `CGPreflightListenEventAccess`
- `CGRequestListenEventAccess`
- `NSEvent.addGlobalMonitorForEvents` for mouse movement
- `NSEvent.addLocalMonitorForEvents` for mouse movement

The implementation may read `NSEvent.mouseLocation` only when a tracking boundary changes, a deadline fires, startup reconciles state, or panel lifecycle changes. It may not poll it continuously.

Clean-room rule:

- Do not clone Atoll into the CornerPet repository.
- Do not paste Atoll source into comments, tests, tickets, or prompts used for implementation.
- Do not reuse Atoll type names, file names, constants, or code structure.
- Use this spec and Apple API documentation as the implementation source of truth.

## 10. Migration and Deletion List

Delete:

- `CornerPet/App/InputMonitoringPermissionCoordinator.swift`
- `CornerPet/HotCorner/MouseMonitor.swift`
- `InputMonitoringPermissionCoordinatorTests` from `CornerPetTests/AppConfigurationTests.swift`
- `MouseMonitorTests` from `CornerPetTests/HotCornerStateMachineTests.swift`
- Permission and mouse-monitor PBX build/file references only

Rewrite or modify:

- `CornerPet/HotCorner/HotCornerStateMachine.swift`
- `CornerPet/App/AppDelegate.swift`
- `CornerPet/Panel/CornerPanel.swift`
- `CornerPet/Panel/CapturePanelController.swift`
- `CornerPetTests/HotCornerStateMachineTests.swift`
- `CornerPetTests/PanelAnimatorTests.swift`
- `CornerPet.xcodeproj/project.pbxproj`

Create:

- `CornerPet/HotCorner/CornerTriggerCoordinator.swift`
- `CornerPet/HotCorner/TriggerZonePanel.swift`
- `CornerPetTests/CornerTriggerCoordinatorTests.swift`
- `CornerPetTests/TriggerZonePanelTests.swift`

Keep without unrelated refactor:

- `CornerPet/HotCorner/HotCornerGeometry.swift` and its current 20 pt thickness change
- `CornerPet/HotCorner/DwellTiming.swift` (the sole dwell duration is 400 ms)
- `CornerPet/Panel/PanelAnimator.swift`
- `CornerPet/Panel/PanelPositioner.swift`
- All signing settings and unrelated PBX edits
- All task/content persistence work, if added by another worker

## 11. Test Strategy

### Pure state-machine tests

- Enter trigger → schedule a 400 ms dwell.
- Move horizontal arm → overlap → vertical arm while union remains true → same deadline token and start time.
- Leave before 400 ms → cancel dwell; stale deadline ignored.
- Deadline at 399 ms → no presentation; at 400 ms with trigger membership → one presentation.
- Deadline with pointer outside → no presentation.
- Panel open + pointer in trigger or panel → no close.
- Leave both → one 100 ms close deadline.
- Re-enter before 100 ms → cancel close; stale deadline ignored.
- Close deadline with pointer still outside → one dismiss.
- Close deadline with pointer back inside → no dismiss.
- Escape from opening/open/closePending → immediate dismiss and deadline cancellation.
- Enter keep-open while closing → one reverse request.
- Non-finite/backward time never presents or dismisses.

### Adapter tests

- Trigger panels have exact main-screen arm frames and required style/configuration.
- Tracking areas contain `.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect` and not `.mouseMoved`.
- Coordinator samples the injected pointer on boundary and deadline callbacks.
- Coordinator schedules/cancels exactly the deadline emitted by the state machine.
- Start/stop are idempotent and stop cancels all pending work.
- AppDelegate starts without a permission object and always creates the trigger coordinator.
- Capture panel is nonactivating, fullscreen auxiliary, emits boundary changes, and handles Escape locally.

### Static forbidden-API check

```bash
if rg -n 'CGPreflightListenEventAccess|CGRequestListenEventAccess|addGlobalMonitorForEvents|addLocalMonitorForEvents' CornerPet CornerPetTests; then
  echo 'Forbidden permission or event-monitor API remains' >&2
  exit 1
fi
if rg -n '\.mouseMoved' CornerPet; then
  echo 'Product source still subscribes to mouseMoved' >&2
  exit 1
fi
```

The test target is allowed to mention `.mouseMoved` only in a negative assertion proving that a tracking area does not contain that option.

## 12. Acceptance Criteria

Automated:

- All focused state-machine, trigger panel, coordinator, panel, geometry, and app-delegate tests pass.
- Full `CornerPetTests` suite passes.
- Debug app build succeeds on arm64 macOS 14+.
- Forbidden-API search returns no matches.
- `project.pbxproj` retains current signing and Panel references and opens through `xcodebuild -list`.

Manual main-screen demonstration:

- CornerPet launches while Input Monitoring is disabled and shows no Input Monitoring request or guidance.
- Enter either top-left arm and remain within the L union for about 400 ms: panel appears once.
- Move from one arm to the other through their overlap: the original dwell is not restarted.
- Leave before 400 ms: panel does not appear.
- Move from trigger into the visible capture panel: panel stays open.
- Leave both trigger and panel for more than 100 ms: panel closes.
- Leave and return inside 100 ms: close is cancelled.
- Press Escape while the panel is open: panel closes.
- Repeat in a fullscreen app's auxiliary space on the main display: trigger and panel remain available without switching Spaces or exiting fullscreen.

## 13. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Tracking callbacks from overlapping panels arrive out of order | Dwell resets between arms | Reconcile every callback with injected global pointer location and union geometry; never trust one arm's exit alone |
| Transparent trigger panels intercept Apple-menu clicks | Main-screen menu interference | Keep exact small frames, test clicking Apple menu, and stop at prototype if unacceptable |
| Nonactivating capture panel cannot receive Escape in some focus states | Escape acceptance fails | Keep responder-chain probe, test with another app frontmost, and do not add a global keyboard monitor as a workaround |
| Fullscreen space ordering differs by macOS version | Trigger/panel hidden behind fullscreen app | Apply fullscreen auxiliary behavior to every involved panel and manually test on supported macOS |
| Cancelled timer fires late | Stale open/close action | Match deadline kind, generation, and due time in the pure state machine |
| Animated panel frame moves under a stationary pointer | False outside decision | Query current `keepOpenFrame` at boundary/lifecycle/deadline time; do not cache final frame |
| Dirty PBX file is regenerated | User signing/Panel work is lost | Patch only explicit file/build references and verify `git diff` before/after |
| GPL contamination | Licensing risk | Implement from this behavior spec and Apple docs; never copy or translate Atoll source |

## 14. Rollback Boundary

The implementation is isolated to the trigger adapter/state machine, AppDelegate wiring, capture-panel tracking integration, tests, and their PBX references. If the prototype fails the menu-interference, fullscreen, or Escape acceptance gate, revert only those feature changes and restore the last known-good `MouseMonitor` path from Git history. Do not roll back the user's signing settings, 20 pt geometry work, Panel animator/positioner work, or unrelated persistence changes.

No database or persisted model migration exists in this change, so rollback has no data compatibility cost.

# Atoll-style Corner Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` for every behavior change and `superpowers:verification-before-completion` before reporting success. Execute tasks inline in this existing worktree; do not create a worktree, commit, push, or open a PR.

**Goal:** Replace CornerPet's permission-gated global mouse-movement monitor with a permission-free, tracking-panel corner trigger that opens after 400 ms and closes 100 ms after leaving the trigger-plus-panel keep-open region.

**Architecture:** Two transparent nonactivating `NSPanel` arm windows emit `NSTrackingArea` boundary events to `CornerTriggerCoordinator`. The coordinator injects monotonic time, pointer location, and deadline scheduling into an AppKit-free `HotCornerStateMachine`; it reconciles every boundary/deadline against the union geometry before presenting, dismissing, or reversing the existing capture panel.

**Tech Stack:** Swift 6, AppKit (`NSPanel`, `NSTrackingArea`, `NSEvent.mouseLocation`), XCTest, Xcode project file

**Spec:** `docs/superpowers/specs/2026-08-26-atoll-style-corner-trigger-design.md`

## Global Constraints

- Work in `/Users/jack/MyApp/CornerPet`; do not create a worktree.
- Do not commit, push, create a PR, or discard unrelated dirty-worktree changes.
- Before every task, re-run `git status --short` and inspect the relevant diff; another worker's changes remain user-owned.
- Main-screen top-left demonstration only.
- Trigger geometry is exactly horizontal 86×20 pt and vertical 20×86 pt on `NSScreen.main.frame`.
- Dwell is the single fixed duration of exactly 0.400 seconds; outside close debounce is exactly 0.100 seconds.
- Use `NSTrackingArea` options `.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`; do not add `.mouseMoved`.
- Do not use global or local mouse-moved event monitors.
- Do not call `CGPreflightListenEventAccess` or `CGRequestListenEventAccess`.
- `NSEvent.mouseLocation` may be sampled only at startup reconciliation, tracking boundaries, panel lifecycle changes, and deadlines; never poll continuously.
- Keep state transitions pure. Inject monotonic clock, pointer provider, and deadline scheduler into the adapter.
- Preserve the current signing team/settings and all unrelated `project.pbxproj` edits.
- Do not copy, translate, or paste Atoll GPL source. Implement only from the spec and Apple public APIs.
- Existing persistence/task content is out of scope.
- The current shell requires `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; do not change global `xcode-select` state.

## Existing Worktree Ownership Snapshot

At plan creation, these files already differ from `HEAD` and must not be blanket-reverted:

```text
 M CornerPet.xcodeproj/project.pbxproj
 M CornerPet/App/AppDelegate.swift
 M CornerPet/HotCorner/HotCornerGeometry.swift
 M CornerPetTests/AppConfigurationTests.swift
 M CornerPetTests/HotCornerGeometryTests.swift
?? CornerPet/App/InputMonitoringPermissionCoordinator.swift
?? CornerPet/Panel/
?? CornerPetTests/PanelAnimatorTests.swift
?? CornerPetTests/PanelPositionerTests.swift
```

The baseline unit command succeeds. The full scheme previously stalled during the UI-test operation after unit tests passed; Task 6 must recheck this after permission gating is gone.

---

### Task 1: Replace pointer-observation lifecycle with a pure deadline state machine

**Files:**

- Rewrite: `CornerPet/HotCorner/HotCornerStateMachine.swift`
- Rewrite tests: `CornerPetTests/HotCornerStateMachineTests.swift`
- Keep: `CornerPet/HotCorner/DwellTiming.swift`
- Keep: `CornerPet/HotCorner/HotCornerGeometry.swift`

**Interfaces:**

- Consumes: reconciled `HotCornerPointerPresence`, monotonic timestamps, exact deadline tokens, panel lifecycle, Escape.
- Produces: `HotCornerStateMachine.handle(_:) -> [HotCornerEffect]`, `nextDeadline`, and deterministic state inspection for tests.

- [ ] **Step 1: Protect the existing dirty state**

Run:

```bash
git status --short
git diff -- CornerPet/HotCorner/HotCornerStateMachine.swift \
  CornerPetTests/HotCornerStateMachineTests.swift
```

Expected: the state-machine files are either clean or their existing changes are understood before editing. Do not restore any file.

- [ ] **Step 2: Replace the old tests with red tests for the new input/effect contract**

Define these test helpers and test cases in `CornerPetTests/HotCornerStateMachineTests.swift`:

```swift
private let outside = HotCornerPointerPresence(
    isInsideTrigger: false,
    isInsidePanel: false
)
private let inHorizontalArm = HotCornerPointerPresence(
    isInsideTrigger: true,
    isInsidePanel: false
)
private let inVerticalArm = HotCornerPointerPresence(
    isInsideTrigger: true,
    isInsidePanel: false
)
private let inPanel = HotCornerPointerPresence(
    isInsideTrigger: false,
    isInsidePanel: true
)

func testStandardDwellPresentsOnceAtExactlySixHundredMilliseconds()
func testMovingBetweenArmsPreservesTheOriginalDwellDeadline()
func testLeavingBeforeDwellCancelsAndStaleDeadlineCannotPresent()
func testDwellDeadlineRechecksPointerAndRefusesOutsidePresence()
func testOpenPanelTreatsTriggerAndPanelAsOneKeepOpenRegion()
func testLeavingAllSurfacesSchedulesOneHundredMillisecondClose()
func testReentryCancelsCloseAndStaleDeadlineCannotDismiss()
func testCloseDeadlineDismissesOnlyWhenPointerIsStillOutside()
func testEscapeDismissesImmediatelyAndCancelsDeadline()
func testReentryWhileClosingRequestsOneReversal()
func testBackwardAndNonFiniteTimeNeverPresentOrDismiss()
```

The arm-switch test must compare the exact deadline token before and after the second `.presenceChanged` event:

```swift
var machine = HotCornerStateMachine(dwellDuration: 0.400, closeDebounce: 0.100)
let firstEffects = machine.handle(.presenceChanged(inHorizontalArm, at: 10))
let deadline = try XCTUnwrap(firstEffects.scheduledDeadline(of: .dwell))

XCTAssertEqual(machine.handle(.presenceChanged(inVerticalArm, at: 10.250)), [])
XCTAssertEqual(machine.nextDeadline, deadline)
XCTAssertEqual(
    machine.handle(.deadlineReached(deadline, presence: inVerticalArm, at: 10.400)),
    [.present]
)
```

- [ ] **Step 3: Run the focused suite and verify a compile-time red state**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/HotCornerStateMachineTests test
```

Expected: FAIL because `HotCornerPointerPresence`, `HotCornerDeadline`, and the new event/effect API do not exist.

- [ ] **Step 4: Implement the model and transition reducer without AppKit**

Use these exact module interfaces in `CornerPet/HotCorner/HotCornerStateMachine.swift`:

```swift
import Foundation

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

enum HotCornerState: Equatable {
    case idle
    case dwelling(startedAt: TimeInterval, deadline: HotCornerDeadline)
    case opening
    case open
    case closePending(deadline: HotCornerDeadline)
    case closing(reverseRequested: Bool)
    case suppressedUntilTriggerExit
}

struct HotCornerStateMachine {
    private let dwellDuration: TimeInterval
    private let closeDebounce: TimeInterval
    private var nextGeneration = 0
    private var lastAcceptedTime: TimeInterval?
    private(set) var state: HotCornerState = .idle
    private(set) var nextDeadline: HotCornerDeadline?

    init(dwellDuration: TimeInterval = DwellTiming.duration,
         closeDebounce: TimeInterval = 0.100)

    mutating func handle(_ event: HotCornerEvent) -> [HotCornerEffect]
}
```

Implement the transition table from design §6.1 and §8. Important details:

- Generate a new deadline only on a real outside→inside-trigger or inside→outside-keep-open transition.
- Preserve the same dwell deadline for repeated inside-trigger presence, including arm-to-arm movement.
- Validate exact token equality and `at >= dueAt` before a deadline effect.
- Emit cancellation before `.dismiss` for Escape when a deadline exists.
- Set `reverseRequested: true` after the first reverse effect so repeated enter callbacks are inert.
- If Escape completion leaves the pointer over the trigger, remain suppressed until one outside-trigger presence arrives.
- Reject non-finite and backwards timestamps before creating a deadline or present/dismiss effect.

- [ ] **Step 5: Run the focused suite to green**

Run the Step 3 command.

Expected: `TEST SUCCEEDED`; all eleven behavior tests pass.

- [ ] **Step 6: Inspect the state-machine diff; do not commit**

Run:

```bash
git diff --check
git diff -- CornerPet/HotCorner/HotCornerStateMachine.swift \
  CornerPetTests/HotCornerStateMachineTests.swift
```

Expected: no whitespace errors; no AppKit import, `NSEvent`, timer, task, controller, or copied Atoll text in the reducer.

---

### Task 2: Add transparent top-left tracking panels

**Files:**

- Create: `CornerPet/HotCorner/TriggerZonePanel.swift`
- Create: `CornerPetTests/TriggerZonePanelTests.swift`
- Project integration deferred to Task 5; for the red/green loop, add both file references and source membership temporarily only if Xcode cannot compile them otherwise, preserving all dirty PBX edits.

**Interfaces:**

- Consumes: exact global arm frame and one `onBoundaryChanged` closure.
- Produces: a transparent, always-on-top, nonactivating panel with one tracking view; mouse entered/exited invoke the closure.

- [ ] **Step 1: Write panel configuration and tracking-area red tests**

Add `@MainActor final class TriggerZonePanelTests: XCTestCase` with:

```swift
func testTriggerPanelIsTransparentNonactivatingAndFullscreenAuxiliary() {
    let panel = TriggerZonePanel(frame: CGRect(x: 0, y: 0, width: 86, height: 20)) {}

    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertFalse(panel.isOpaque)
    XCTAssertEqual(panel.backgroundColor, .clear)
    XCTAssertFalse(panel.hasShadow)
    XCTAssertEqual(panel.level, .statusBar)
    XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
}

func testTrackingAreaUsesBoundaryEventsInAllVisibleSpacesWithoutMouseMoved() {
    let panel = TriggerZonePanel(frame: CGRect(x: 0, y: 0, width: 86, height: 20)) {}
    let area = try XCTUnwrap(panel.trackingView.trackingAreas.first)

    XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
    XCTAssertTrue(area.options.contains(.activeAlways))
    XCTAssertTrue(area.options.contains(.inVisibleRect))
    XCTAssertFalse(area.options.contains(.mouseMoved))
}
```

Also test the horizontal/vertical frames returned by a factory for a negative-origin screen:

```swift
let frames = TriggerZonePanel.frames(
    for: CGRect(x: -1512, y: 0, width: 1512, height: 982),
    corner: .topLeft
)
XCTAssertEqual(frames.horizontal, CGRect(x: -1512, y: 962, width: 86, height: 20))
XCTAssertEqual(frames.vertical, CGRect(x: -1512, y: 896, width: 20, height: 86))
```

- [ ] **Step 2: Run the focused test to red**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/TriggerZonePanelTests test
```

Expected: FAIL because `TriggerZonePanel` does not exist.

- [ ] **Step 3: Implement the trigger panel and tracking view**

Use this structure:

```swift
import AppKit

@MainActor
final class TriggerZonePanel: NSPanel {
    struct ArmFrames: Equatable {
        let horizontal: CGRect
        let vertical: CGRect
    }

    let trackingView: TriggerTrackingView

    init(frame: CGRect, onBoundaryChanged: @escaping () -> Void) {
        trackingView = TriggerTrackingView(onBoundaryChanged: onBoundaryChanged)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = trackingView
        // Apply every configuration required by design §6.3.
    }

    static func frames(for screenFrame: CGRect, corner: TriggerCorner) -> ArmFrames
}

@MainActor
final class TriggerTrackingView: NSView {
    let onBoundaryChanged: () -> Void
    // updateTrackingAreas() removes the prior owned area and installs one
    // .mouseEnteredAndExited/.activeAlways/.inVisibleRect area.
    override func mouseEntered(with event: NSEvent) { onBoundaryChanged() }
    override func mouseExited(with event: NSEvent) { onBoundaryChanged() }
}
```

For this scope, `frames(for:corner:)` supports `.topLeft` as the production path. It may continue mirroring all four corners only if the existing geometry helpers make that trivial; do not broaden runtime selection.

- [ ] **Step 4: Run the focused test to green and inspect forbidden options**

Run the Step 2 command, then:

```bash
if rg -n 'add(Global|Local)MonitorForEvents|\.mouseMoved' \
  CornerPet/HotCorner/TriggerZonePanel.swift; then exit 1; fi
```

Expected: test succeeds and search returns no matches.

- [ ] **Step 5: Inspect the diff; do not commit**

Run `git diff --check` and inspect both new files plus any surgical PBX edits. Confirm no existing signing/build setting changed.

---

### Task 3: Build the injected coordinator and deadline scheduler

**Files:**

- Create: `CornerPet/HotCorner/CornerTriggerCoordinator.swift`
- Create: `CornerPetTests/CornerTriggerCoordinatorTests.swift`
- Modify only if needed for read-only access: `CornerPet/Panel/CapturePanelController.swift`

**Interfaces:**

- Consumes: main-screen provider, `HotCornerClock`, `PointerLocationProvider`, `HotCornerDeadlineScheduling`, panel keep-open frame/lifecycle, and state-machine effects.
- Produces: two managed trigger panels; idempotent `start()`/`stop()`; `panelBeganOpening`, `panelDidOpen`, `panelBeganClosing`, `panelDidClose`, `escapePressed`, and `refreshPresence` adapters.

- [ ] **Step 1: Write a manual scheduler and coordinator red tests**

In `CornerPetTests/CornerTriggerCoordinatorTests.swift`, define test doubles with no real sleep:

```swift
@MainActor
final class ManualDeadlineScheduler: HotCornerDeadlineScheduling {
    final class Token: HotCornerCancellation {
        var isCancelled = false
        let operation: @MainActor () -> Void
        init(operation: @escaping @MainActor () -> Void) { self.operation = operation }
        func cancel() { isCancelled = true }
    }

    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var tokens: [Token] = []

    func schedule(after delay: TimeInterval,
                  operation: @escaping @MainActor () -> Void) -> HotCornerCancellation {
        scheduledDelays.append(delay)
        let token = Token(operation: operation)
        tokens.append(token)
        return token
    }

    func fire(_ index: Int) { tokens[index].operation() }
}
```

Add tests:

```swift
func testStartCreatesExactMainScreenTopLeftPanelsAndStopOrdersThemOut()
func testBoundarySamplesInjectedPointerAndSchedulesSixHundredMilliseconds()
func testMovingBetweenArmFramesDoesNotReplaceTheDwellToken()
func testDwellFireRechecksPointerBeforePresenting()
func testOutsideOpenPanelSchedulesOneHundredMilliseconds()
func testReentryCancelsCloseAndFiringStaleTokenDoesNotDismiss()
func testCloseFireRechecksPointerBeforeDismissing()
func testStartAndStopAreIdempotentAndStopCancelsEveryToken()
```

Use mutable injected values:

```swift
var now: TimeInterval = 20
var pointer = CGPoint(x: 10, y: 990)
var presented = 0
var dismissed = 0
let scheduler = ManualDeadlineScheduler()
```

The arm-switch test must move `pointer` from the horizontal-exclusive area to the vertical-exclusive area and call the boundary hook for each panel; assert only one 0.400 schedule was recorded.

- [ ] **Step 2: Run the coordinator suite to red**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/CornerTriggerCoordinatorTests test
```

Expected: FAIL because coordinator and scheduling protocols do not exist.

- [ ] **Step 3: Implement scheduling interfaces and the main-run-loop adapter**

Use the spec signatures and add a production scheduler in the coordinator file:

```swift
typealias HotCornerClock = @MainActor () -> TimeInterval
typealias PointerLocationProvider = @MainActor () -> CGPoint

protocol HotCornerCancellation: AnyObject { func cancel() }

protocol HotCornerDeadlineScheduling: AnyObject {
    @MainActor
    func schedule(after delay: TimeInterval,
                  operation: @escaping @MainActor () -> Void) -> HotCornerCancellation
}

@MainActor
final class MainRunLoopDeadlineScheduler: HotCornerDeadlineScheduling
```

The production scheduler may wrap `Timer` or a cancellable `Task`; it schedules one-shot work only and never samples pointer location itself.

- [ ] **Step 4: Implement `CornerTriggerCoordinator` effect handling**

Required initializer shape:

```swift
@MainActor
final class CornerTriggerCoordinator {
    init(
        screenProvider: @escaping () -> NSScreen?,
        panelFrameProvider: @escaping () -> CGRect?,
        clock: @escaping HotCornerClock = { ProcessInfo.processInfo.systemUptime },
        pointerLocationProvider: @escaping PointerLocationProvider = { NSEvent.mouseLocation },
        scheduler: HotCornerDeadlineScheduling = MainRunLoopDeadlineScheduler(),
        presentPanel: @escaping (UInt32) -> Void,
        dismissPanel: @escaping () -> Void,
        reverseClosingPanel: @escaping (UInt32) -> Void
    )

    @discardableResult func start() -> Bool
    func stop()
    func refreshPresence()
    func panelBeganOpening()
    func panelDidOpen()
    func panelBeganClosing()
    func panelDidClose()
    func escapePressed()
}
```

Implementation requirements:

1. `start()` obtains `NSScreen.main`, its display ID, and exact arm frames; creates/orders both panels; then reconciles once.
2. `refreshPresence()` reads the pointer exactly once, evaluates the L union through `HotCornerGeometry.contains`, evaluates the current panel frame, and sends `.presenceChanged`.
3. `.schedule(deadline)` cancels only the prior token of the same kind and schedules `max(0, dueAt - clock())`.
4. The scheduled closure re-samples pointer/panel membership and sends `.deadlineReached` with the captured exact deadline.
5. `.cancelDeadline(kind)` cancels and clears that kind.
6. `.present` calls the injected present closure with the captured main-screen display ID.
7. `.dismiss` and `.reverseClosing` call only their injected closures.
8. `stop()` cancels both deadline tokens, orders out both trigger panels, drops references, resets the state machine, and is safe twice.

- [ ] **Step 5: Run focused state and coordinator suites**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/HotCornerStateMachineTests \
  -only-testing:CornerPetTests/CornerTriggerCoordinatorTests test
```

Expected: `TEST SUCCEEDED`; no real timer or pointer dependency is used by tests.

- [ ] **Step 6: Inspect pointer sampling sites; do not commit**

Run:

```bash
rg -n 'NSEvent\.mouseLocation|pointerLocationProvider' \
  CornerPet/HotCorner/CornerTriggerCoordinator.swift
git diff --check
```

Expected: production default injection plus explicit boundary/deadline reconciliation; no loop or repeating timer reads the pointer.

---

### Task 4: Integrate keep-open tracking and nonactivation into the capture panel

**Files:**

- Modify: `CornerPet/Panel/CornerPanel.swift`
- Modify: `CornerPet/Panel/CapturePanelController.swift`
- Modify tests: `CornerPetTests/PanelAnimatorTests.swift`
- Keep: `CornerPet/Panel/PanelAnimator.swift`
- Keep: `CornerPet/Panel/PanelPositioner.swift`

**Interfaces:**

- Consumes: existing panel presentation/dismiss/reversal lifecycle.
- Produces: `keepOpenFrame`, `onPointerBoundaryChanged`, local `onEscape`, nonactivating capture panel, and unchanged animation semantics.

- [ ] **Step 1: Snapshot the untracked Panel files before editing**

Run:

```bash
git status --short CornerPet/Panel CornerPetTests/PanelAnimatorTests.swift
sed -n '1,260p' CornerPet/Panel/CapturePanelController.swift
```

Expected: Panel files are user-owned/untracked. Edit them in place; do not delete and recreate the folder.

- [ ] **Step 2: Add red tests for nonactivation, tracking, keep-open frame, and Escape forwarding**

Update/add these tests in `CornerPetTests/PanelAnimatorTests.swift`:

```swift
func testPanelIsNonactivatingFloatingAndFullscreenAuxiliary() {
    let panel = CornerPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 400))
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertEqual(panel.level, .floating)
    XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
}

func testControllerExposesCurrentKeepOpenFrameOnlyWhileVisible()
func testCaptureTrackingAreaUsesBoundaryOptionsWithoutMouseMoved()
func testCaptureBoundaryCallbackForwardsToCoordinatorHook()
func testEscapeForwardsBeforeDismissAndDoesNotInstallGlobalMonitor()
func testPresentDoesNotActivateTheApplication()
```

Replace the current test that expects `applicationActivatorForPanel` to be called. Preserve existing animation/reversal/lifecycle tests.

- [ ] **Step 3: Run the panel tests to red**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/CornerPanelTests \
  -only-testing:CornerPetTests/PanelTickerAndControllerTests test
```

Expected: FAIL on missing `.nonactivatingPanel`, keep-open/tracking hooks, and obsolete activation expectation.

- [ ] **Step 4: Make the minimal capture-panel changes**

In `CornerPanel.swift`, construct with:

```swift
styleMask: [.borderless, .nonactivatingPanel]
```

In `CapturePanelController.swift`:

```swift
var onPointerBoundaryChanged: (() -> Void)?
var onEscape: (() -> Void)?

var keepOpenFrame: CGRect? {
    isVisible ? panel?.frame : nil
}
```

Make the existing Escape content probe install a tracking area with the three required options, forward both `mouseEntered` and `mouseExited`, and call `onEscape` before `dismiss()`. Remove `applicationActivatorForPanel` and `NSApp.activate()` from the opening path. Keep responder-chain Escape handling local; do not add an event monitor.

Call `onPointerBoundaryChanged` after animation frame samples/lifecycle edges only if needed to reconcile a stationary pointer against a moving frame; do not call it at a 60 Hz rate. The required points are start opening, finish opening, start closing, reverse, and finish closing.

- [ ] **Step 5: Run panel and coordinator regressions**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/PanelAnimatorTests \
  -only-testing:CornerPetTests/CornerTriggerCoordinatorTests test
```

Expected: `TEST SUCCEEDED`; existing animation tests remain green.

- [ ] **Step 6: Inspect the Panel diff; do not commit**

Confirm the animator and positioner are unchanged unless a failing regression proves a targeted change is necessary. Confirm no `NSApp.activate`, global monitor, or mouse-moved tracking option was added.

---

### Task 5: Remove permission gating and migrate Xcode project membership

**Files:**

- Modify: `CornerPet/App/AppDelegate.swift`
- Delete: `CornerPet/App/InputMonitoringPermissionCoordinator.swift`
- Delete: `CornerPet/HotCorner/MouseMonitor.swift`
- Modify tests: `CornerPetTests/AppConfigurationTests.swift`
- Modify tests: `CornerPetTests/HotCornerStateMachineTests.swift`
- Modify tests: `CornerPetTests/PanelAnimatorTests.swift`
- Modify surgically: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**

- Consumes: `CapturePanelController`, `CornerTriggerCoordinator`, main screen.
- Produces: unconditional permission-free launch wiring and idempotent termination cleanup.

- [ ] **Step 1: Write/replace AppDelegate integration tests first**

Remove `InputMonitoringPermissionCoordinatorTests`, `authorizedPermission()`, and denied-permission launch tests. Replace AppDelegate integration coverage with:

```swift
func testLaunchAlwaysCreatesMainScreenTopLeftTriggerWithoutPermissionGate()
func testTerminationStopsTriggerCoordinator()
func testPanelLifecycleAndBoundaryCallbacksReachCoordinator()
func testPresentDismissAndReverseReuseOneCapturePanelController()
```

Use injected factories or closures so tests do not order real trigger windows when verifying AppDelegate wiring.

- [ ] **Step 2: Run AppDelegate tests to red**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/AppDelegateIntegrationTests \
  -only-testing:CornerPetTests/AppConfigurationTests test
```

Expected: FAIL because AppDelegate still requires permission injection and owns `MouseMonitor`.

- [ ] **Step 3: Rewire AppDelegate without authorization**

Replace these properties:

```swift
private let inputMonitoringPermission: InputMonitoringPermissionCoordinator
private var mouseMonitor: MouseMonitor?
private(set) var isMonitoring = false
```

with ownership of one capture controller and one `CornerTriggerCoordinator`. Production launch must:

```swift
let panelController = CapturePanelController(
    screenProvider: Self.screen(withID:),
    corner: .topLeft
)

let triggerCoordinator = CornerTriggerCoordinator(
    screenProvider: { NSScreen.main },
    panelFrameProvider: { [weak panelController] in panelController?.keepOpenFrame },
    presentPanel: { [weak panelController] screenID in panelController?.present(screenID: screenID) },
    dismissPanel: { [weak panelController] in panelController?.dismiss() },
    reverseClosingPanel: { [weak panelController] screenID in
        panelController?.reverseClosing(screenID: screenID)
    }
)
```

Wire capture lifecycle, capture boundary, and Escape callbacks to coordinator methods. Start once after wiring; stop once on termination. Keep test seams `@MainActor` and minimal.

- [ ] **Step 4: Delete obsolete source and test blocks**

Delete exactly:

```text
CornerPet/App/InputMonitoringPermissionCoordinator.swift
CornerPet/HotCorner/MouseMonitor.swift
InputMonitoringPermissionCoordinatorTests in AppConfigurationTests.swift
MouseMonitorTests in HotCornerStateMachineTests.swift
```

Do not delete geometry, fixed dwell timing, panel animation, positioner, signing, or unrelated tests.

- [ ] **Step 5: Surgically update `project.pbxproj`**

Before editing, save a visible diff in the terminal:

```bash
git diff -- CornerPet.xcodeproj/project.pbxproj
```

Then:

- remove file reference and Sources build-file entries only for `InputMonitoringPermissionCoordinator.swift` and `MouseMonitor.swift`;
- add file reference and app Sources entries for `CornerTriggerCoordinator.swift` and `TriggerZonePanel.swift`;
- add file reference and test Sources entries for `CornerTriggerCoordinatorTests.swift` and `TriggerZonePanelTests.swift`;
- retain all existing Panel group/references;
- retain `DEVELOPMENT_TEAM = BA2HVLXM26`, automatic signing, deployment target, architectures, product identifiers, and every unrelated UUID/build setting;
- do not regenerate the project file.

- [ ] **Step 6: Validate project structure and focused integration tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -list

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests/AppDelegateIntegrationTests \
  -only-testing:CornerPetTests/CornerTriggerCoordinatorTests \
  -only-testing:CornerPetTests/TriggerZonePanelTests test
```

Expected: project lists normally and focused tests succeed.

- [ ] **Step 7: Prove the permission/global-monitor path is gone**

Run:

```bash
if rg -n 'InputMonitoringPermissionCoordinator|CGPreflightListenEventAccess|CGRequestListenEventAccess|addGlobalMonitorForEvents|addLocalMonitorForEvents|MouseMonitor' \
  CornerPet CornerPetTests CornerPet.xcodeproj/project.pbxproj; then
  echo 'Obsolete permission or mouse-moved monitor path remains' >&2
  exit 1
fi
if rg -n '\.mouseMoved' CornerPet; then
  echo 'Product source still subscribes to mouseMoved' >&2
  exit 1
fi
```

Expected: no matches and exit 0.

- [ ] **Step 8: Review the complete product diff; do not commit**

Run:

```bash
git diff --check
git status --short
git diff --stat
git diff -- CornerPet.xcodeproj/project.pbxproj
```

Expected: only scoped trigger/panel/app/test/project changes plus pre-existing user changes; signing diff remains intact.

---

### Task 6: Full verification and manual main-screen/fullscreen demonstration

**Files:**

- Verify: all scoped source and test files
- Update only if results require documentation: `tasks/plan.md`, `tasks/todo.md`

**Interfaces:**

- Consumes: completed tasks 1–5.
- Produces: automated and manual evidence for every acceptance criterion; no commit.

- [ ] **Step 1: Run all unit tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData \
  -only-testing:CornerPetTests test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build the Debug app and retry the complete scheme once**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData build

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS' -derivedDataPath DerivedData test
```

Expected: Debug `BUILD SUCCEEDED`. Full scheme should finish after removal of the launch permission prompt. If UI test still stalls, capture the `.xcresult`, stop after one bounded retry, and report it separately; do not weaken unit coverage or add sleeps.

- [ ] **Step 3: Run static architecture guards**

Run:

```bash
if rg -n 'CGPreflightListenEventAccess|CGRequestListenEventAccess|addGlobalMonitorForEvents|addLocalMonitorForEvents' \
  CornerPet CornerPetTests; then exit 1; fi
if rg -n '\.mouseMoved' CornerPet; then exit 1; fi

rg -n 'NSTrackingArea|mouseEntered|mouseExited|activeAlways|inVisibleRect|nonactivatingPanel|fullScreenAuxiliary' \
  CornerPet/HotCorner/TriggerZonePanel.swift \
  CornerPet/Panel/CornerPanel.swift \
  CornerPet/Panel/CapturePanelController.swift
```

Expected: forbidden search has no output; required architecture search shows trigger/capture tracking and panel flags.

- [ ] **Step 4: Prepare the manual demonstration without changing privacy state programmatically**

1. In System Settings → Privacy & Security → Input Monitoring, confirm CornerPet is disabled or absent.
2. Quit any running CornerPet instance.
3. Launch `DerivedData/Build/Products/Debug/CornerPet.app`.
4. Confirm no permission prompt or guidance dialog appears.

- [ ] **Step 5: Verify dwell and arm-union behavior on the main screen**

1. Approach the top-left horizontal arm, leave before 400 ms, and confirm no panel.
2. Enter the horizontal-exclusive area and remain for about 400 ms; confirm one open.
3. Close with Escape.
4. Re-enter the horizontal-exclusive area, move through the 20×20 overlap into the vertical-exclusive area without leaving the L union, and ensure total continuous dwell reaches 400 ms; confirm the timer did not restart.
5. Hold within one arm beyond one second and confirm no duplicate presentation.

- [ ] **Step 6: Verify keep-open and close debounce**

1. With the panel open, move trigger → panel; confirm it stays open.
2. Move panel → trigger; confirm it stays open.
3. Leave both for less than 100 ms and return; confirm close cancels.
4. Leave both for more than 100 ms; confirm close starts.
5. Re-enter while a reversible close is running; confirm it reverses at most once and remains usable.
6. Press Escape while open; confirm immediate close without activating a permission prompt.

- [ ] **Step 7: Verify fullscreen auxiliary-space behavior**

1. Put Finder/Safari/Xcode into fullscreen on the main display.
2. Without leaving that fullscreen Space, dwell at the main screen's top-left L trigger.
3. Confirm trigger/panel appear in the same Space, do not exit fullscreen, and do not switch Spaces.
4. Move into the panel, leave/re-enter under 100 ms, then leave over 100 ms; confirm keep-open behavior matches desktop mode.

- [ ] **Step 8: Check interaction hazards**

1. With CornerPet running, click the Apple menu and nearby menu-bar controls.
2. Record whether either 86×20/20×86 transparent arm blocks essential clicks.
3. With another app frontmost, open CornerPet and press Escape; confirm the nonactivating panel receives it.
4. If either Apple-menu access or Escape fails, stop the rollout at this prototype gate. Do not add a global event monitor to mask the problem.

- [ ] **Step 9: Final scope and rollback review**

Run:

```bash
git status --short
git diff --check
git diff --stat
git diff --name-status
```

Confirm:

- no persistence/task-content files changed;
- no Atoll source or copied identifiers exist;
- no permission/global-monitor API remains;
- the deletion list is exact;
- all pre-existing signing and unrelated work remains;
- no commit exists for this implementation session.

If acceptance fails, roll back only the new trigger coordinator/panels, rewritten trigger state machine, AppDelegate wiring, capture tracking integration, tests, and their PBX references. Preserve signing, 20 pt geometry, Panel animator/positioner, and unrelated user changes.

## Acceptance Matrix

| Requirement | Automated evidence | Manual evidence |
|---|---|---|
| No Input Monitoring | forbidden-API scan; AppDelegate tests | launch with permission disabled, no prompt |
| 86×20 + 20×86 top-left L | geometry/panel-frame tests | pointer probe on main screen |
| 400 ms dwell | state + coordinator tests | early exit and continuous dwell |
| Arm movement does not reset | same-token state/coordinator tests | horizontal→overlap→vertical |
| Trigger + panel keep-open | state/controller tests | trigger↔panel movement |
| 100 ms close with pointer recheck | state/coordinator stale-token tests | leave/re-enter vs leave/stay out |
| Escape closes | panel/controller tests | frontmost-other-app Escape |
| Transparent/nonactivating/tracking | TriggerZonePanel/CornerPanel tests | no Space switch or app activation surprise |
| Fullscreen auxiliary | panel flag tests | fullscreen main-display demonstration |
| Clean-room GPL boundary | source/diff review | no external source imported |

## Handoff Notes for Luna

1. The hardest correctness issue is not the 400 ms timer; it is overlapping-panel event ordering. Always re-evaluate the whole L union from the injected pointer provider before changing dwell state.
2. Timer cancellation is advisory. The state machine must reject stale dwell/close tokens by exact generation and due time.
3. `NSEvent.mouseLocation` and `NSScreen.frame` already share global AppKit coordinates. An unnecessary window-coordinate conversion will break negative-origin and fullscreen behavior.
4. Do not regenerate `project.pbxproj`; it contains user signing and untracked Panel integration.
5. Do not restore `InputMonitoringPermissionCoordinator.swift` or replace the design with a polling timer when UI tests are awkward.
6. A nonactivating panel receiving Escape is a manual gate. If AppKit focus behavior fails, report the product tradeoff; a global key monitor is out of scope.
7. The transparent arm panels may intercept the Apple menu. Treat that as a real prototype risk, not a test artifact.

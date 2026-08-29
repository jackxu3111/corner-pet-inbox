# CornerPet Test Environment

## Why the UI runner exists

macOS UI automation can fail before CornerPet reaches a product assertion when an input-method candidate window or another process owns focus. `Scripts/run-ui-tests.sh` makes that environment deterministic without changing the user's enabled input methods or machine-wide Xcode selection.

The runner records the current keyboard input-source ID, temporarily selects `com.apple.keylayout.ABC`, and sends an Escape event directly to the now-inactive input source process when it is still running. This dismisses candidate windows that can survive a source switch and steal XCUITest focus without changing the frontmost app or stopping the input-method process. It then runs `CornerPetUITests` serially and restores the exact captured source ID from an exit trap. Restoration runs after success, test failure, `INT`, or `TERM`.

The input-source helper uses the public HIToolbox APIs declared by the installed macOS SDK: `TISCopyCurrentKeyboardInputSource`, `TISCreateInputSourceList`, and `TISSelectInputSource`. It uses `CGEvent.postToPid` only for candidate-window cleanup; it never terminates a process or enables, disables, or removes an input source. Run UI automation only when no text composition needs to be preserved, because Escape intentionally cancels any stale composition owned by that input method.

## Commands

Verify Xcode and input-source switching/restoration without launching tests:

```bash
Scripts/run-ui-tests.sh --preflight-only
```

Run all UI tests:

```bash
Scripts/run-ui-tests.sh
```

Run the runner's isolated contract tests. These use fake input-source and Xcode commands and never touch system input settings:

```bash
/bin/bash Scripts/Tests/run-ui-tests-tests.sh
```

The runner checks `CORNERPET_DEVELOPER_DIR`, then the existing `DEVELOPER_DIR`, then `/Applications/Xcode.app`, then `/Applications/Xcode-beta.app`. It passes the chosen path only to its child processes and does not call `xcode-select`.

## Evidence

By default, a real run writes:

```text
build/test-evidence/<timestamp>/CornerPetUITests.log
build/test-evidence/<timestamp>/CornerPetUITests.xcresult
```

The final output names both paths and prints exactly one classification line:

```text
CORNERPET_UI_TEST_ORIGINAL_INPUT_SOURCE=<captured-id>
CORNERPET_UI_TEST_ACTIVE_INPUT_SOURCE=com.apple.keylayout.ABC
CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE=<captured-id>
CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE_STATE=escape-posted|unchanged
CORNERPET_UI_TEST_CLASSIFICATION=<classification>
```

The `QUIESCED` line is omitted when ABC was already active.

| Classification | Exit | Meaning |
|---|---:|---|
| `passed` | 0 | XCUITest completed successfully and the input source was restored. |
| `preflight-passed` | 0 | Xcode/helper/input-source preflight completed and the original source was restored. |
| `environment-preflight` | 64 | Full Xcode, the helper, input-source switching, or inactive input-method cleanup was unavailable before tests started. |
| `product-regression` | 65 | The app launched and xcodebuild reported a test failure without a known automation-infrastructure signature. |
| `automation-infrastructure` | 70 | The log reports an automation-session, app-launch, accessibility, candidate-window, or input-method failure before a trustworthy product assertion. |
| `input-source-restore-failed` | 74 | The original input source could not be restored or verified. This always makes the run fail. |
| `interrupted` | 130/143 | The runner received `INT` or `TERM`; restoration was still attempted. |

Classification never converts a failed assertion into a passing result. Preserve the log and `.xcresult` when investigating ambiguous failures.

## Restoration failure recovery

The runner prints `CORNERPET_UI_TEST_ORIGINAL_INPUT_SOURCE=<id>` before switching. If it ends with `input-source-restore-failed`:

1. Select the original input source from the macOS input menu.
2. Confirm it is active in System Settings > Keyboard > Text Input.
3. Run `Scripts/run-ui-tests.sh --preflight-only` again.
4. Do not rerun the full UI suite until preflight returns 0.

Do not edit `com.apple.HIToolbox` defaults, restart the input-method service, or remove an input method as recovery.

## Reading failures

- Treat missing Xcode, helper compilation, automation permission, and input-source restoration as environment problems.
- Treat session-establishment, focus capture, and candidate-window interception as automation-infrastructure problems and retain the log.
- Treat a reached CornerPet assertion as a product regression and reproduce it with the focused UI test plus the nearest unit-level behavior test.

Full-screen Spaces, physical multi-display behavior, a live Chinese candidate window, pointer drag/resize, sleep/wake, logout/restart, and login launch remain session-dependent manual checks even when the automated suite passes.

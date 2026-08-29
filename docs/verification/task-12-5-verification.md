# CornerPet Task 12.5 Verification

**Date:** 2026-08-29
**Branch:** `codex/cornerpet-task-12-5`
**Original base:** `origin/main` at Task 12 merge `9ede8d7`
**Current remote state:** `origin/main` remains at the earlier Task 12.5 merge `930d3df`; the verified follow-up drift guard and isolated-VM work at `1ef99aa` are not integrated.
**Result:** The local Task 12.5 follow-up passed the reopened gate in the dedicated VM: 13 runner contracts, a 1-test background probe, and exactly 21 guarded UI tests all passed with zero failures. Task 13 remains blocked only until this verified follow-up history is safely integrated into `origin/main`.

## Post-verification merge audit

The merge audit reproduced two guarded UI failures on the unchanged Task 12.5 tree. The immediate `TISSelectInputSource` check reported ABC, but `com.bytedance.inputmethod.doubaoime.pinyin` selected itself again during the XCUITest session and exposed candidate/input-source UI that captured focus. The two completed runs each executed 21 tests with 19 passes and 2 failures and were classified as automation infrastructure.

A new runner contract treats a source found away from ABC at suite end as `input-source-drift` (exit 75), restores the captured source, and rejects an otherwise successful Xcode result. That runner and the unchanged product suite have now passed in an isolated ABC-only VM at `1ef99aa`.

## Environment

```text
macOS:       27.0 (26A5421a)
Architecture: arm64
Xcode:       27.0 beta (27A5228h)
Swift:       6.4
Deployment:  macOS 14.0, arm64
```

The isolated guest selected `/Applications/XcodeCLI.app/Contents/Developer`, a compatibility link to an extended-attribute-free clone of the verified Xcode 27 toolchain. The original damaged `/Applications/Xcode-beta.app` remains preserved and unselected. No Gatekeeper setting was weakened.

## Task 12 integration

Task 12 was reviewed and freshly verified before integration: 341 unit tests and 21 UI tests passed with zero failures. GitHub PR #1 merged it into `main` as `9ede8d7`. The source branch `codex/cornerpet-task-12` was retained, and no force-push or branch deletion was used.

## Automated verification

| Gate | Result | Evidence |
|---|---|---|
| UI runner contract | 13 passed | Guest `ui-runner-contract.log` under the external `1ef99aa-vm-final` evidence directory |
| Release workflow contract | 11 passed | `build/test-evidence/task12-5-final/release-contract.log` |
| SwiftData focused persistence regression | 37 passed, 0 failed | Xcode result bundle `Test-CornerPet-2026.08.29_13-53-36-+0800.xcresult` under DerivedData |
| Full unit suite | 344 passed, 0 failed | `build/test-evidence/task12-5-final/CornerPetUnitTests.xcresult` and `unit-tests.log` |
| Historical guarded UI suite | 21 passed, 0 failed | `build/test-evidence/20260829-142402/CornerPetUITests.xcresult` and `CornerPetUITests.log`; invalidated as the current release gate by the later reproducible drift |
| Isolated-VM unit smoke | 4 passed, 0 failed | `AppConfigurationTests.xcresult` and `unit-smoke.log` under the external `1ef99aa-vm-final` evidence directory |
| Isolated-VM background probe | 1 passed, 0 failed | External evidence directory `1ef99aa-20260829-024510-probe`; VirtualBuddy was hidden and the run used SSH only |
| Current isolated-VM guarded UI suite | **21 passed, 0 failed** | External evidence directory `1ef99aa-20260829-024030`; independently inspected `.xcresult` reports exactly 21 tests |
| Debug clean build | `CLEAN SUCCEEDED`, `BUILD SUCCEEDED` | `build/test-evidence/task12-5-final/debug-build.log` |
| Static analysis | `ANALYZE SUCCEEDED` | `build/test-evidence/task12-5-final/analyze.log` |
| Unsigned Release arm64 build | `CLEAN SUCCEEDED`, `BUILD SUCCEEDED` | `build/test-evidence/task12-5-final/release-build.log` |
| Isolated-VM unsigned Release arm64 build | `CLEAN SUCCEEDED`, `BUILD SUCCEEDED` | External `1ef99aa-vm-final/release-build-after-reboot.log`; version 0.1.0 (1), bundle ID `com.jack.CornerPet`, `LSUIElement=true` |
| Shell syntax and Swift helper warnings-as-errors | passed | final verification console output |
| Whitespace, scope, credential-filename, and excluded-SDK scans | passed | `build/test-evidence/task12-5-final/static-scan.log` and final branch gate |

Build evidence under `build/` is intentionally ignored by Git. Result-bundle and log paths identify the local artifacts used for this acceptance; they are not release packages.

### Isolated VM acceptance

The final isolated run tested `1ef99aa0977759474ddc9eb6142ea6c19f30f8e8` on macOS 27.0 (26A5421a), Xcode 27.0 (27A5228h), and Swift 6.4. The guest had four virtual CPUs, 8 GiB RAM, NAT networking, automatic login, SSH, Developer Mode, unattended Automation Mode enablement, and only `com.apple.keylayout.ABC` installed and selected.

`CORNERPET_AD_HOC_SIGNING=1 Scripts/run-ui-tests.sh --probe-only` passed 1/1 after VirtualBuddy was hidden. No host UI automation was used during that probe. The full `CORNERPET_AD_HOC_SIGNING=1 Scripts/run-ui-tests.sh` run then passed exactly 21/21, with zero failed, skipped, or expected-failure tests and runner classification `passed`. ABC was selected before and after the run. Local ad-hoc signing was used only for VM test products and does not alter the production Release signing configuration.

The independent `.xcresult` summary contains one Xcode QoS priority-inversion runtime warning and no test failure. Binary evidence remains outside Git at `/Users/jack/.codex/vm/CornerPet-UI-Test/exchange/task-12-5-evidence/`; each accepted run has a text summary alongside its log and result bundle.

### Input-method failure reproduction and fix

The first final UI attempt recorded a visible interruption from `com.bytedance.inputmethod.doubaoime` after the selected source had already changed to ABC. `LibraryFlowUITests.testArchiveAndFavoritesSearchAndCommandF()` then failed its focus assertion. The runner correctly classified that 21-test run as `automation-infrastructure`, not a product regression; its retained evidence is under `build/test-evidence/20260829-140814/`.

The root cause was a stale candidate window owned by the still-running input-method process. The final runner now:

1. captures the exact input-source ID;
2. selects `com.apple.keylayout.ABC`;
3. sends Escape directly to the inactive input-method PID to dismiss stale composition UI;
4. runs UI tests serially;
5. restores and verifies the captured source on every exit path.

The final real preflight and UI run started and ended with `com.bytedance.inputmethod.doubaoime.pinyin`. The Doubao input-method PID remained `11742` before and after preflight and after the suite, proving that the runner did not terminate its process. The final log contains no Doubao, candidate-window, or UI-interruption record, and the previously failing Command-F path passed.

### SwiftData compatibility

`CornerPetSchemaV1` freezes the Task 12 `Draft` and `IdeaItem` shapes at `1.0.0`. Every container uses `CornerPetMigrationPlan`; there are no speculative stages.

`CornerPetTests/Fixtures/Task12Legacy.store` was written by the pre-versioning Task 12 schema and contains only synthetic data. The migration test copies it, opens it through V1, checks the draft and every item field, closes it, then reopens the same migrated copy and repeats the assertions. The production configuration remains `CornerPetContent`, and no recovery path deletes or recreates a failed store.

### Release baseline

The effective Release settings were verified as:

```text
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Developer ID Application
ENABLE_HARDENED_RUNTIME = YES
ENABLE_TESTABILITY = NO
```

`Scripts/release.sh local-build` produced a non-distribution arm64 app at `build/release/unsigned/CornerPet.app`. Its Info.plist reports version `0.1.0`, build `1`, bundle ID `com.jack.CornerPet`, and `LSUIElement=true`.

`Scripts/release.sh preflight` stopped with `no Developer ID Application identity is installed` before calling `notarytool`. This is the expected truthful result on this Mac. No signed, notarized, stapled, Gatekeeper-approved, or installed release is claimed.

## Historical regression matrix

These entries describe the earlier recorded run and do not close the reopened isolated-VM gate.

| Path | Status | Evidence or boundary |
|---|---|---|
| Capture input, Return, Shift-Return, Escape, draft reopen | Passed automated | Unit and CaptureFlow UI suites |
| Archive, undo, favorites, search, edit, and delete | Passed automated | Unit and LibraryFlow UI suites |
| Four-corner geometry and reminder placement | Passed automated | Geometry/positioning unit tests and reminder four-corner UI test |
| Reminder open, dismiss, snooze, daily and wake policies | Passed automated | Reminder unit tests and ReminderFlow UI suite |
| Pin toggle, keep-open, size/state persistence | Passed automated | Pinning UI and persistence unit tests |
| SwiftData Task 12 store upgrade and second reopen | Passed automated | Legacy-store migration test |
| Input-source switch, candidate cleanup, and exact restoration | Passed automated/real environment | Contract tests, real preflight, and final guarded UI run |
| Product use with a live Chinese composition session | Not executed | Runner cleanup was verified; actual Chinese composition remains a user-session acceptance check |
| Finder/Safari/Xcode full-screen Spaces | Not executed | Requires interactive multi-app Space switching |
| Physical multi-display attach/detach and all four corners | Not executed | Only one physical display was available |
| Pointer drag and resize of the pinned panel | Not executed | Requires trusted physical-pointer observation |
| Real sleep/wake reminder delivery | Not executed | Requires a controlled sleep/wake session |
| Developer ID archive, notarization, stapling, and Gatekeeper | Blocked by external prerequisite | Developer ID certificate and notary keychain profile are absent |
| `/Applications` install and installed-app runtime check | Not executed | Must use a signed, notarized, stapled app |
| Login launch after logout or restart | Not executed | Requires the installed app and a real user-authorized login/restart |

Not-executed checks are not treated as passes. The exact operator steps and recovery paths are in `docs/testing.md` and `docs/release.md`.

## Code-quality review

The Task 12.5 diff was reviewed in test-first order across correctness, readability, architecture, security, and performance, with SwiftUI/SwiftData-specific checks.

- **Critical:** none.
- **Required, resolved:** Xcode could not clean a pre-created custom Release output directory; the script now leaves ownership to the build system and has a regression test.
- **Required, resolved:** install destinations accepted unsafe path shapes; artifact and Applications paths must now be absolute and cannot be `/` or the project root.
- **Required, resolved:** installed-process verification could match an unrelated `CornerPet` process; it now matches the installed executable's full path.
- **Required, resolved:** Release had testability enabled; it is now explicitly disabled.
- **Required, resolved:** switching to ABC alone did not dismiss a stale candidate window. Directed Escape cleanup removes it without terminating the input method, and the exact source is restored.
- **Required, resolved:** end-of-suite input-source drift could replace a product or interruption exit status. Drift now overrides only an otherwise successful Xcode result while restoration still runs on every exit path.
- **Required, resolved:** drift restoration was insufficiently covered. Contracts now cover ABC-original restoration, product failure plus drift, and interruption plus drift.
- **Required, resolved:** the documented guarded probe was not executable. `--probe-only` now selects the single launch test through the production guard.
- **Required, resolved:** the status document described the reopened gate inconsistently. Current and historical evidence are now separated explicitly.
- **Required, resolved:** two specification lines had trailing whitespace and a stale approval status.
- **Optional, pre-existing:** Xcode 27 beta emits 50 Swift 6 concurrency warnings in unchanged test files and 21 XCUITest main-thread warnings plus one QoS warning. Product Debug/Release builds and analysis succeed; these warnings are retained as Task 14 toolchain-cleanup debt rather than expanded into an unrelated test refactor.
- **Informational:** AppIntents metadata extraction reports that no AppIntents dependency exists. CornerPet does not use AppIntents, so this is an Xcode build-pipeline notice rather than a product defect.

No cloud sync, analytics SDK, automatic updater, global event tap, input-monitoring dependency, or pet/page visual redesign was added.

## External prerequisites and handoff

To complete a real distribution acceptance, Jack still needs:

1. a valid `Developer ID Application` certificate and private key for team `BA2HVLXM26`;
2. a named `notarytool` keychain profile;
3. a credentialed archive/notarize/staple/Gatekeeper run;
4. explicit installation into `/Applications`;
5. a real logout or restart for Launch at Login verification;
6. the interactive full-screen, physical multi-display, drag/resize, Chinese composition, and sleep/wake checks above.

After the verified follow-up is present on `origin/main`, Task 13 may begin localization, accessibility, Reduce Motion, and user-facing error-copy work without redesigning the current UI. Task 14 should then add privacy-safe metrics, clean up Xcode 27 test warnings, execute the extended hardware/session matrix, and start the seven-day release-candidate record.

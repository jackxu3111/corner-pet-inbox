# CornerPet Task 12.5 Verification

**Date:** 2026-08-29
**Branch:** `codex/cornerpet-task-12-5`
**Base:** `origin/main` at Task 12 merge `9ede8d7`
**Result:** Executable local gates passed. Credentialed distribution and session-dependent checks remain explicit external gates.

## Environment

```text
macOS:       27.0 (26A5421a)
Architecture: arm64
Xcode:       27.0 beta (27A5228h)
Swift:       6.4
Deployment:  macOS 14.0, arm64
```

The host's system developer directory initially pointed to Command Line Tools. Every project command selected `/Applications/Xcode-beta.app/Contents/Developer` only for that process; Task 12.5 did not change the machine-wide `xcode-select` value.

## Task 12 integration

Task 12 was reviewed and freshly verified before integration: 341 unit tests and 21 UI tests passed with zero failures. GitHub PR #1 merged it into `main` as `9ede8d7`. The source branch `codex/cornerpet-task-12` was retained, and no force-push or branch deletion was used.

## Automated verification

| Gate | Result | Evidence |
|---|---|---|
| UI runner contract | 7 passed | `build/test-evidence/task12-5-final/ui-runner-contract.log` |
| Release workflow contract | 11 passed | `build/test-evidence/task12-5-final/release-contract.log` |
| SwiftData focused persistence regression | 37 passed, 0 failed | Xcode result bundle `Test-CornerPet-2026.08.29_13-53-36-+0800.xcresult` under DerivedData |
| Full unit suite | 344 passed, 0 failed | `build/test-evidence/task12-5-final/CornerPetUnitTests.xcresult` and `unit-tests.log` |
| Final guarded UI suite | 21 passed, 0 failed | `build/test-evidence/20260829-142402/CornerPetUITests.xcresult` and `CornerPetUITests.log` |
| Debug clean build | `CLEAN SUCCEEDED`, `BUILD SUCCEEDED` | `build/test-evidence/task12-5-final/debug-build.log` |
| Static analysis | `ANALYZE SUCCEEDED` | `build/test-evidence/task12-5-final/analyze.log` |
| Unsigned Release arm64 build | `CLEAN SUCCEEDED`, `BUILD SUCCEEDED` | `build/test-evidence/task12-5-final/release-build.log` |
| Shell syntax and Swift helper warnings-as-errors | passed | final verification console output |
| Whitespace, scope, credential-filename, and excluded-SDK scans | passed | `build/test-evidence/task12-5-final/static-scan.log` and final branch gate |

Build evidence under `build/` is intentionally ignored by Git. Result-bundle and log paths identify the local artifacts used for this acceptance; they are not release packages.

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

## Regression matrix

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

Task 13 is next: finish localization, accessibility, Reduce Motion, and user-facing error copy without redesigning the current UI. Task 14 should then add privacy-safe metrics, clean up Xcode 27 test warnings, execute the extended hardware/session matrix, and start the seven-day release-candidate record.

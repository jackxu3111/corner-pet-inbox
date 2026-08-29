# CornerPet Task 12.5 Engineering Hardening Design

**Date:** 2026-08-29  
**Status:** Approved in conversation; awaiting repository-spec review  
**Scope:** Engineering hardening only. No pet or page visual redesign, cloud sync, analytics SDK, or automatic updater.

## 1. Objective

Prepare the Task 12 codebase for reliable ongoing development and a first manually operated macOS release workflow without expanding product scope.

Task 12.5 must:

1. Integrate the reviewed Task 12 change into `main` through a traceable pull request.
2. Make UI-test setup repeatable when a Chinese input method or focus state can interfere with automation.
3. Establish the existing SwiftData model as a versioned V1 schema and prove that existing data upgrades without loss.
4. Add the minimum release baseline for versioning, Release builds, Hardened Runtime, Developer ID signing, notarization, packaging, installation, and login-launch verification.
5. Record automated and manual regression evidence while distinguishing product failures from environment failures.

## 2. Current Baseline

- Task 12 was a single commit on top of Task 11 and passed pre-merge review.
- Fresh pre-merge verification passed 341 unit tests and 21 UI tests with zero failures.
- The first test invocation failed because the active developer directory pointed to Command Line Tools. Selecting Xcode Beta for that process made the same tests pass. This is an environment failure, not a product regression.
- The successful UI run used the ABC keyboard layout. The reported Chinese candidate-window failure did not reproduce, so Task 12.5 must add a deterministic guard instead of claiming a product fix.
- SwiftData currently uses an unversioned `Schema([Draft.self, IdeaItem.self])` and the existing `CornerPetContent` store name.
- The project has no marketing version, build number, Hardened Runtime setting, release script, entitlements file, or release runbook.
- The current Mac has a valid Apple Development identity but no Developer ID Application identity. Local unsigned Release validation is possible; Developer ID signing and notarization are external gates.

## 3. Git Integration Strategy

Task 12 is integrated independently before Task 12.5 development:

1. Create a Task 12 pull request against `main` containing review and regression evidence.
2. Merge through GitHub without force-pushing or deleting the source branch.
3. Create `codex/cornerpet-task-12-5` from the updated `origin/main`.
4. Commit Task 12.5 in small, reviewable stages: specification and plan, UI-test environment, SwiftData migration, release baseline, then final evidence and documentation.

This preserves a clean boundary between the already accepted product feature and the engineering work that follows it.

## 4. UI Automation Environment

### 4.1 Design

Add a project-owned UI-test runner with a small native input-source helper.

The runner will:

1. Resolve an available full Xcode installation without changing the machine-wide `xcode-select` setting.
2. Capture the exact current keyboard input-source identifier.
3. Switch temporarily to the ABC keyboard layout only when the current source is unsuitable for deterministic UI automation.
4. Register cleanup before changing the input source and restore the captured source on normal exit, test failure, interruption, or termination.
5. Run UI tests serially and retain the build log and result-bundle path.
6. Classify the final result as an environment preflight failure, automation infrastructure failure, or product test failure.

The runner must not disable an input method, rewrite the user's enabled-input-source list, kill the input-method service, or persistently change system defaults.

### 4.2 Failure Classification

- **Environment preflight:** no usable Xcode, input source cannot be queried or restored, automation permission is unavailable, or a stale test session prevents launch.
- **Automation infrastructure:** test runner cannot establish or retain an application session, focus is captured outside the app, or candidate-window/input-service behavior prevents interaction before a product assertion runs.
- **Product regression:** CornerPet launches and the test reaches a product assertion that fails.

The classification is diagnostic evidence. It must not turn a failed product assertion into a passing result.

### 4.3 Tests

Before the real system integration is implemented, test the orchestration against fake input-source and test-runner commands. Cover:

- no switch when ABC is already active;
- switch and restore after success;
- restore after test failure;
- restore after interruption or early exit;
- explicit failure if the original source cannot be restored;
- preservation of the underlying test command's exit status when cleanup succeeds.

The real helper receives a read-only preflight check plus a reversible manual smoke test on the current Mac.

## 5. SwiftData Versioning and Migration

### 5.1 V1 Schema

Introduce `CornerPetSchemaV1: VersionedSchema` containing the exact released `Draft` and `IdeaItem` shapes. The V1 schema must preserve current field types, uniqueness constraints, optionality, and persisted entity identity. It must not add speculative future fields.

Introduce `CornerPetMigrationPlan: SchemaMigrationPlan` with V1 as its only schema and no fabricated migration stage. Future data-shape changes will add a new immutable schema version and an explicit lightweight or custom stage.

`ModelContainerFactory` will construct its schema from V1, pass the migration plan to `ModelContainer`, and retain the existing `CornerPetContent` store name and URL behavior.

### 5.2 Compatibility Proof

The migration tests must exercise a store written in the pre-Task-12.5 unversioned format. A test that creates and reopens only a new versioned store is insufficient.

The compatibility fixture or legacy writer will include:

- a draft with non-empty text and a stable timestamp;
- idea items in multiple buckets;
- stable identifiers and creation/update/move timestamps;
- archived data represented by the current bucket model.

Pinned-window persistence is stored outside SwiftData and remains part of the separate restart regression matrix.

The versioned container must open the same store and return equivalent values. A second reopen verifies persistence after migration. Failed migration must surface as an error and must not delete, recreate, or silently replace the original store.

## 6. Release Engineering Baseline

### 6.1 Project Settings

Use `0.1.0` as the initial marketing version and `1` as the initial build number. Add generated Info.plist version keys and enable Hardened Runtime for Release.

Keep local development builds usable with Apple Development signing. The release workflow must explicitly require a `Developer ID Application` identity for distributable artifacts and must fail before packaging when that identity is absent.

### 6.2 Release Workflow

Add a checked-in release script and runbook with explicit stages:

1. **Preflight:** validate Xcode, bundle version/build number, Developer ID identity, notarization keychain profile, clean input artifact paths, and expected bundle identifier.
2. **Local validation:** build the Release configuration with signing disabled when external credentials are unavailable; inspect the resulting bundle and build settings.
3. **Archive/sign:** create a Release archive using Developer ID Application signing and Hardened Runtime.
4. **Verify signature:** run strict code-signature verification before submission.
5. **Package/notarize:** package the app as a ZIP, submit with `notarytool --wait` using a named keychain profile, obtain the notarization log on failure, staple the accepted ticket, then repeat strict signature verification and perform Gatekeeper assessment.
6. **Install:** copy the verified app to `/Applications` only through an explicit command. Refuse to overwrite an existing installation unless replacement is explicitly requested.
7. **Runtime acceptance:** launch the installed LSUIElement app, verify that it remains running without an unintended Dock presence, exercise CornerPet, and verify the login-item flow after a user-authorized login or restart.

Credentials must never be accepted as committed command-line literals or stored in the repository. The runbook will document how the operator creates the keychain profile outside the project.

### 6.3 Honest External Gates

Without a Developer ID Application certificate and notarization credentials, Task 12.5 can verify:

- project settings;
- unsigned local Release build;
- script preflight and safe failure behavior;
- artifact packaging logic that does not claim distribution readiness.

It cannot claim successful Developer ID signing, Gatekeeper acceptance, Apple notarization, stapling, `/Applications` distribution acceptance, or login-after-restart verification.

## 7. Regression and Acceptance Matrix

### 7.1 Automated

- all `CornerPetTests`;
- all `CornerPetUITests` through the guarded runner;
- input-source restoration tests;
- legacy SwiftData upgrade and reopen tests;
- Release build with signing disabled;
- build-setting checks for version, build number, Release configuration, and Hardened Runtime;
- static checks including `git diff --check` and confirmation that no prohibited APIs or product-scope expansions were introduced.

### 7.2 Manual or Hardware/Session Dependent

- Chinese input candidate window and focus behavior;
- all four corners across full-screen Spaces and available displays;
- reminder arrival and snooze across wake or date rollover;
- archive, favorite, search, edit, delete, and pin behavior;
- pinned-window drag and resize;
- state restoration after app restart;
- installed-app Gatekeeper behavior and login launch after logout or restart.

Each manual item is recorded as passed, failed, or not executed with its blocking prerequisite. Not executed is never reported as passed.

## 8. Error Handling and Data Safety

- No script may permanently change the selected or enabled input methods.
- Input-source restoration failure is a test-run failure that requires user-visible remediation.
- Migration code must never delete the production store as recovery behavior.
- Release scripts must use explicit artifact paths and refuse ambiguous overwrite operations.
- Git operations must not force-push, delete user branches, or discard unrelated changes.
- Failures caused by missing Apple credentials must stop at preflight and list the exact missing prerequisite.

## 9. Documentation and Completion Evidence

Update the task plan and checklist with:

- Task 12 PR and merge commit;
- exact test commands, counts, timestamps, and result-bundle paths;
- SwiftData migration fixture and assertions;
- Release build and build-setting evidence;
- Developer ID/notarization prerequisites still owned by the user;
- manual regression status;
- Task 13/14 handoff recommendations.

Task 12.5 is complete when the scoped changes are reviewed, automated verification passes, known external gates are accurately documented, small commits are pushed to `origin/codex/cornerpet-task-12-5`, and no user data or unrelated workspace changes have been overwritten.

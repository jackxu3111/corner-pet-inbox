# CornerPet Task 12.5 Engineering Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden CornerPet's test environment, SwiftData persistence, and macOS release workflow while preserving Task 12 behavior and user data.

**Architecture:** Keep the three hardening concerns independent: a reversible shell-orchestrated UI-test environment, a frozen SwiftData V1 schema with an explicit migration plan, and a fail-fast release pipeline whose credentialed stages remain external gates. Each concern is test-first, independently committed, and joined only by the final regression and evidence documents.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SwiftData, Carbon HIToolbox, XCTest/XCUITest, POSIX shell, Xcode 27 beta, macOS 27, macOS 14 deployment target, arm64

**Spec:** `docs/superpowers/specs/2026-08-29-task-12-5-engineering-hardening-design.md`

## Global Constraints

- Work only on `codex/cornerpet-task-12-5` in `/Users/jack/.codex/worktrees/a224/CornerPet`.
- Do not modify `/Users/jack/MyApp/CornerPet`, force-push, delete branches, or discard unrelated changes.
- Do not permanently change selected or enabled input methods; restoration failure is a test-run failure.
- Preserve the `CornerPetContent` store location and all Task 12 data fields.
- Do not add cloud sync, analytics SDKs, automatic update infrastructure, external visual assets, or pet/page visual redesign.
- Keep macOS 14 and arm64 as the product baseline.
- Use marketing version `0.1.0` and build number `1`.
- Do not store Apple credentials in the repository or report credentialed signing/notarization as successful without direct evidence.
- Execute each behavior change with RED → GREEN → focused regression → atomic commit.

---

### Task 1: Planning, Tracking, and Baseline Evidence

**Files:**
- Create: `docs/superpowers/plans/2026-08-29-task-12-5-engineering-hardening.md`
- Modify: `tasks/plan.md`
- Modify: `tasks/todo.md`

**Interfaces:**
- Consumes: approved Task 12.5 specification, Task 12 PR #1, merge commit `9ede8d7`, and fresh Task 12 test evidence.
- Produces: the executable checklist for Tasks 2–6 and accurate project-level task status.

- [x] **Step 1: Record Task 12 integration and Task 12.5 scope**

Mark Tasks 10–12 complete where their accepted branches and automated evidence exist. Add Task 12.5 as an in-progress engineering gate before Task 13, while leaving session-dependent manual checks explicitly open.

- [x] **Step 2: Record the baseline classifications**

Document:

```text
Task 12 unit baseline: 341 passed, 0 failed
Task 12 UI baseline: 21 passed, 0 failed
Initial xcodebuild failure: environment (Command Line Tools selected)
Successful UI input source: com.apple.keylayout.ABC
```

- [x] **Step 3: Self-review the plan against every specification section**

Run:

```bash
rg -n 'T[B]D|T[O]DO:|implement[[:space:]]+later|fill[[:space:]]+in[[:space:]]+details|add[[:space:]]+appropriate' docs/superpowers/plans/2026-08-29-task-12-5-engineering-hardening.md
git diff --check
```

Expected: no placeholder matches and no whitespace errors.

- [x] **Step 4: Commit the planning increment**

```bash
git add docs/superpowers/plans/2026-08-29-task-12-5-engineering-hardening.md tasks/plan.md tasks/todo.md
git commit -m "docs: plan Task 12.5 engineering hardening"
```

---

### Task 2: Reversible UI-Test Environment

**Files:**
- Create: `Scripts/UIAutomation/InputSource.swift`
- Create: `Scripts/run-ui-tests.sh`
- Create: `Scripts/Tests/run-ui-tests-tests.sh`
- Create: `docs/testing.md`

**Interfaces:**
- Consumes: `TISCopyCurrentKeyboardInputSource`, `TISCreateInputSourceList`, `TISSelectInputSource`, a full Xcode developer directory, and `xcodebuild test`.
- Produces: `InputSource current|select <id>`, `run-ui-tests.sh`, deterministic classification lines, retained logs/result bundles, and exact input-source restoration.

- [x] **Step 1: Write failing shell tests for the runner contract**

Use fake commands injected through `CORNERPET_INPUT_SOURCE_TOOL` and `CORNERPET_XCODEBUILD`. The fake input-source tool stores its current ID in a temporary file. Cover:

```text
ABC already active -> no select call
Chinese input active -> select ABC -> execute tests -> restore Chinese
xcodebuild exit 65 -> restore Chinese -> product-regression classification -> exit 65
automation launch error -> restore Chinese -> automation-infrastructure classification -> exit 70
TERM while xcodebuild runs -> restore Chinese -> nonzero signal exit
restore command fails -> input-source-restore-failed classification -> exit 74
```

- [x] **Step 2: Run the shell tests and verify RED**

Run:

```bash
/bin/bash Scripts/Tests/run-ui-tests-tests.sh
```

Expected: FAIL because `Scripts/run-ui-tests.sh` does not exist.

- [x] **Step 3: Implement the native input-source helper**

Provide this command surface:

```swift
enum Command {
    case current
    case select(identifier: String)
}
```

`current` prints only the current input-source identifier. `select` queries enabled sources by `kTISPropertyInputSourceID`, requires a selectable source, invokes `TISSelectInputSource`, then verifies the selected identifier. All failures write a concise error to stderr and return nonzero.

- [x] **Step 4: Implement the minimal runner**

The runner must:

```text
resolve Xcode -> build/helper preflight -> capture original input source
install EXIT/INT/TERM cleanup -> switch to com.apple.keylayout.ABC if needed
run serial CornerPetUITests -> classify failure -> restore original -> return truthful status
```

Use exit codes 64 for preflight, 65 for product regression, 70 for automation infrastructure, and 74 for restoration failure. Print exactly one final `CORNERPET_UI_TEST_CLASSIFICATION=<value>` line.

- [x] **Step 5: Run shell tests until GREEN**

Run:

```bash
/bin/bash Scripts/Tests/run-ui-tests-tests.sh
```

Expected: every fake-environment scenario passes and the final line reports the test count.

- [x] **Step 6: Exercise the real helper reversibly**

Run:

```bash
Scripts/run-ui-tests.sh --preflight-only
```

Capture the input-source ID before and after and require equality. Do not select a different source when ABC is already current.

- [x] **Step 7: Run the real guarded UI suite**

Run:

```bash
Scripts/run-ui-tests.sh
```

Expected: result classification reflects the actual suite outcome, the original input source is restored, and the output names the log and `.xcresult` paths.

- [x] **Step 8: Document environment versus product failures**

In `docs/testing.md`, include normal usage, `--preflight-only`, exit-code meanings, retained evidence locations, Xcode resolution, non-persistent input-source behavior, and recovery commands when restoration fails.

- [x] **Step 9: Review and commit the UI-test increment**

```bash
git diff --check
/bin/bash -n Scripts/run-ui-tests.sh Scripts/Tests/run-ui-tests-tests.sh
/bin/bash Scripts/Tests/run-ui-tests-tests.sh
git add Scripts/UIAutomation/InputSource.swift Scripts/run-ui-tests.sh Scripts/Tests/run-ui-tests-tests.sh docs/testing.md
git commit -m "test: stabilize macOS UI automation environment"
```

---

### Task 3: SwiftData V1 Schema and Existing-Store Migration

**Files:**
- Create: `CornerPet/Persistence/CornerPetSchema.swift`
- Modify: `CornerPet/Persistence/Draft.swift`
- Modify: `CornerPet/Persistence/IdeaItem.swift`
- Modify: `CornerPet/Persistence/ModelContainerFactory.swift`
- Modify: `CornerPetTests/ModelContainerFactoryTests.swift`
- Create: `CornerPetTests/Fixtures/Task12Legacy.store`
- Modify: `CornerPet.xcodeproj/project.pbxproj`
- Create: `docs/persistence.md`

**Interfaces:**
- Consumes: the exact Task 12 `Draft` and `IdeaItem` shapes and `CornerPetContent` configuration.
- Produces: `CornerPetSchemaV1`, `CornerPetMigrationPlan`, stable top-level `Draft`/`IdeaItem` aliases, and a factory that always supplies the migration plan.

- [x] **Step 1: Generate a synthetic legacy fixture before changing production models**

Temporarily add a test-only generator to `ModelContainerFactoryTests` that uses the current unversioned factory to write synthetic data with fixed UUIDs, all three buckets, and fixed timestamps. Run only the generator, checkpoint WAL data into the main SQLite file, place the result at `CornerPetTests/Fixtures/Task12Legacy.store`, then remove the generator method before committing.

The fixture contains synthetic strings only and no user data.

- [x] **Step 2: Write failing migration and schema tests**

Add tests that assert:

```swift
XCTAssertEqual(CornerPetSchemaV1.versionIdentifier, .init(1, 0, 0))
XCTAssertEqual(CornerPetMigrationPlan.schemas.count, 1)
XCTAssertTrue(CornerPetMigrationPlan.stages.isEmpty)
```

Locate the fixture relative to `#filePath`, copy `Task12Legacy.store` to a temporary directory, open the copy with `ModelContainerFactory.make(at:)`, and assert exact draft text/date plus exact item UUID, text, bucket, and timestamps. Close and reopen the same migrated copy and assert the same values again. The fixture is source test data, not a test-bundle resource.

- [x] **Step 3: Run focused tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -only-testing:CornerPetTests/ModelContainerFactoryTests
```

Expected: compilation fails because the versioned schema and migration plan do not exist.

- [x] **Step 4: Implement the frozen V1 schema**

Create:

```swift
enum CornerPetSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Draft.self, IdeaItem.self] }
}

enum CornerPetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CornerPetSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

Move each `@Model` into an extension of `CornerPetSchemaV1` in its existing focused file and expose top-level aliases:

```swift
typealias Draft = CornerPetSchemaV1.Draft
typealias IdeaItem = CornerPetSchemaV1.IdeaItem
```

Do not change stored properties or defaults.

- [x] **Step 5: Route every container through the migration plan**

Use:

```swift
private static var schema: Schema { Schema(versionedSchema: CornerPetSchemaV1.self) }

return try ModelContainer(
    for: schema,
    migrationPlan: CornerPetMigrationPlan.self,
    configurations: [configuration]
)
```

Keep `CornerPetContent`, test configuration names, CloudKit disabled state, and store URL behavior unchanged.

- [x] **Step 6: Add project references and run focused tests until GREEN**

Run the command from Step 3 and require exact fixture migration plus second reopen to pass.

- [x] **Step 7: Run all persistence tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -only-testing:CornerPetTests/ModelContainerFactoryTests \
  -only-testing:CornerPetTests/DraftStoreTests \
  -only-testing:CornerPetTests/ItemStoreTests \
  -only-testing:CornerPetTests/ItemLifecycleTests
```

- [x] **Step 8: Document the migration contract**

In `docs/persistence.md`, explain V1 immutability, how to add V2 and a migration stage, the unchanged store location, fixture provenance, backup expectations, and the prohibition on deleting a failed production store.

- [x] **Step 9: Review and commit the persistence increment**

```bash
git diff --check
git add CornerPet/Persistence CornerPetTests/ModelContainerFactoryTests.swift CornerPetTests/Fixtures/Task12Legacy.store CornerPet.xcodeproj/project.pbxproj docs/persistence.md
git commit -m "feat: version the SwiftData persistence schema"
```

---

### Task 4: Release Configuration and Safe Distribution Workflow

**Files:**
- Create: `Scripts/release.sh`
- Create: `Scripts/Tests/release-tests.sh`
- Modify: `CornerPet.xcodeproj/project.pbxproj`
- Create: `docs/release.md`

**Interfaces:**
- Consumes: Xcode, `security`, `codesign`, `ditto`, `notarytool`, `stapler`, `spctl`, a Developer ID Application identity, and a named notarytool keychain profile.
- Produces: `local-build`, `preflight`, `archive`, `notarize`, `install`, and `verify-installed` release commands plus auditable artifacts under `build/release`.

- [x] **Step 1: Write failing release contract tests**

Use temporary fake command directories plus `CORNERPET_APPLICATIONS_DIR` and command-path environment overrides, so no test writes to the real `/Applications`. Assert:

```text
local-build passes Release, arm64, and CODE_SIGNING_ALLOWED=NO
preflight rejects a missing Developer ID Application identity
preflight rejects a missing notary profile without printing credentials
install rejects an existing /Applications target without --replace
install --replace moves the prior app to a recoverable backup path
unknown commands and unsafe artifact paths fail with usage
```

Add a build-setting assertion that expects `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`, `ENABLE_HARDENED_RUNTIME = YES`, and Release `CODE_SIGN_IDENTITY = Developer ID Application`.

- [x] **Step 2: Run the release tests and verify RED**

Run:

```bash
/bin/bash Scripts/Tests/release-tests.sh
```

Expected: FAIL because the release script and build settings do not exist.

- [x] **Step 3: Add the project release settings**

For the CornerPet app target:

```text
Debug:  MARKETING_VERSION=0.1.0, CURRENT_PROJECT_VERSION=1
Release: MARKETING_VERSION=0.1.0, CURRENT_PROJECT_VERSION=1
Release: ENABLE_HARDENED_RUNTIME=YES
Release: CODE_SIGN_STYLE=Manual
Release: CODE_SIGN_IDENTITY=Developer ID Application
```

Keep Debug on Apple Development signing. Do not add hardened-runtime exceptions or unrelated entitlements.

- [x] **Step 4: Implement local-build and credential preflight**

`local-build` performs a clean unsigned Release arm64 build into an explicit artifact directory. `preflight` requires an exact Developer ID Application identity and validates the named keychain profile with `notarytool history`; it must stop before archiving if either prerequisite is absent.

- [x] **Step 5: Implement archive, verification, packaging, and notarization**

The credentialed flow must:

```text
xcodebuild archive with manual Developer ID signing
codesign --verify --deep --strict --verbose=2
ditto -c -k --keepParent CornerPet.app CornerPet-0.1.0-1.zip
xcrun notarytool submit ... --keychain-profile ... --wait --output-format json
xcrun stapler staple CornerPet.app
xcrun stapler validate CornerPet.app
codesign strict verification
spctl --assess --type execute --verbose=2
repackage the stapled app
```

On notarization failure, extract the submission ID from JSON and request `notarytool log` without hiding the original failure.

- [x] **Step 6: Implement recoverable installation and runtime inspection**

`install` requires a stapled, Gatekeeper-accepted app. If `/Applications/CornerPet.app` exists, reject by default; with `--replace`, move it to a timestamped backup under `build/release/backups` before copying the new bundle. `verify-installed` checks Info.plist version/build/LSUIElement, launches the app, and confirms the process exists. It reports login-after-restart as a manual gate rather than changing the user's setting.

- [x] **Step 7: Run release tests until GREEN**

Run:

```bash
/bin/bash -n Scripts/release.sh Scripts/Tests/release-tests.sh
/bin/bash Scripts/Tests/release-tests.sh
```

- [x] **Step 8: Run the verifiable local release stages**

Run:

```bash
Scripts/release.sh local-build
Scripts/release.sh preflight
```

Expected on this Mac: local build succeeds; preflight fails truthfully because no Developer ID Application identity is installed. Do not run notarization or `/Applications` replacement without the prerequisites.

- [x] **Step 9: Document the operator runbook**

In `docs/release.md`, record certificate creation, keychain-profile setup, commands for every stage, artifact layout, failure recovery, notarization-log inspection, installation backup behavior, and the manual logout/restart login-item checklist. Cite the Apple Developer ID, Hardened Runtime, and notarization documentation.

- [x] **Step 10: Review and commit the release increment**

```bash
git diff --check
git add Scripts/release.sh Scripts/Tests/release-tests.sh CornerPet.xcodeproj/project.pbxproj docs/release.md
git commit -m "build: add the macOS release baseline"
```

---

### Task 5: Full Regression, Manual Matrix, and Quality Review

**Files:**
- Create: `docs/verification/task-12-5-verification.md`
- Modify: `docs/superpowers/plans/2026-08-29-task-12-5-engineering-hardening.md`
- Modify: `tasks/plan.md`
- Modify: `tasks/todo.md`
- Modify: any Task 12.5 file only when a confirmed review finding requires a fix

**Interfaces:**
- Consumes: all Task 12.5 increments and the Task 12 behavior baseline.
- Produces: fresh automated evidence, an explicit manual/not-executed matrix, five-axis review findings, and corrected task tracking.

- [x] **Step 1: Run script tests and static checks**

```bash
/bin/bash Scripts/Tests/run-ui-tests-tests.sh
/bin/bash Scripts/Tests/release-tests.sh
/bin/bash -n Scripts/run-ui-tests.sh Scripts/release.sh Scripts/Tests/*.sh
git diff --check origin/main...HEAD
rg -n "CGEventTap|NSEvent\.addGlobalMonitor|UNUserNotificationCenter|Sparkle|Sentry|Firebase" CornerPet Scripts
```

- [x] **Step 2: Run all unit tests serially**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -only-testing:CornerPetTests
```

Record the exact executed/passed/failed counts and `.xcresult` path.

- [x] **Step 3: Run all UI tests through the guarded runner**

```bash
Scripts/run-ui-tests.sh
```

Record the classification, exact executed/passed/failed counts, original/restored input-source IDs, log path, and `.xcresult` path.

- [x] **Step 4: Run clean Debug and unsigned Release builds**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild clean build \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64'
Scripts/release.sh local-build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild analyze \
  -project CornerPet.xcodeproj -scheme CornerPet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

- [x] **Step 5: Record the regression matrix truthfully**

Automated evidence covers reminder, archive, favorites, capture/focus, four-corner geometry, screen coordination, pin state, and persistence. Record full-screen/Spaces, physical multi-display behavior, candidate-window behavior under a real Chinese input session, pointer drag/resize, sleep/wake, logout/restart, and `/Applications` login launch as manual passed/failed/not executed. Never convert not executed into passed.

- [x] **Step 6: Conduct the five-axis and SwiftUI/SwiftData review**

Review `origin/main...HEAD` in this order: tests, implementation, project settings/scripts, then documentation. Categorize findings as Critical, Required, Optional, or Nit across correctness, readability, architecture, security, and performance. Fix every confirmed Critical/Required issue with a reproducing test first, rerun the affected verification, and record the resolution.

- [x] **Step 7: Update tracking and commit final evidence**

Mark Task 12.5 complete only when all executable gates pass and external gates are listed. Keep Task 13 as the next task and Task 14 as the later metrics/extended-QA gate.

```bash
git add docs/verification/task-12-5-verification.md docs/superpowers/plans/2026-08-29-task-12-5-engineering-hardening.md tasks/plan.md tasks/todo.md
git commit -m "docs: record Task 12.5 verification evidence"
```

---

### Task 6: Final Branch Verification and Push

**Files:**
- No planned source changes; any change here must correspond to a verified final-review defect.

**Interfaces:**
- Consumes: the complete Task 12.5 branch and all recorded evidence.
- Produces: a clean, pushed `origin/codex/cornerpet-task-12-5` ready for Jack's acceptance.

- [x] **Step 1: Verify repository state and scope**

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff --check origin/main...HEAD
```

- [x] **Step 2: Run the final changed-code gate**

Run the full unit suite, guarded UI suite, unsigned Release build, script tests, and static scans again only if code changed after Task 5 evidence. Read each exit status and failure count before making completion claims.

- [x] **Step 3: Push without rewriting history**

```bash
git push -u origin codex/cornerpet-task-12-5
```

Confirm the remote ref resolves to local `HEAD`. Do not force-push and do not delete Task 12 or Task 12.5 branches.

- [x] **Step 4: Hand off to Task 13**

Report completed items, evidence, branch/commit/remote state, missing Developer ID/notary/manual-session prerequisites, and recommend Task 13 localization/accessibility work next. Task 14 remains responsible for privacy-safe metrics, extended QA, and the seven-day release-candidate record.

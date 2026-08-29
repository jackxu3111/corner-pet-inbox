# CornerPet Task 13 Localization and Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a complete English/Simplified Chinese runtime language baseline plus VoiceOver and 120 ms Reduce Motion acceptance for all existing CornerPet MVP surfaces.

**Architecture:** Add one native String Catalog and a typed `L10n` resource namespace. Propagate the observable `AppSettings` locale through SwiftUI hosts and explicitly refresh AppKit text-view accessibility properties; keep motion policy small and testable.

**Tech Stack:** Swift 6.4, SwiftUI, AppKit, Foundation localization, XCTest/XCUITest, Xcode 27 beta, macOS 14 deployment target, arm64.

**Spec:** `docs/superpowers/specs/2026-08-29-task-13-localization-accessibility-design.md`

## Global Constraints

- Base commit is exactly `8711a8b`; implementation branch is `codex/cornerpet-task-13`.
- First release supports only `en` and `zh-Hans`; default is the autoupdating macOS locale.
- Do not redesign pets or pages and do not add cloud sync, analytics, automatic updates, or third-party dependencies.
- Preserve SwiftData schemas, user content, stable accessibility identifiers, and unrelated changes.
- Use failing behavior tests before production changes and commit each green increment.
- Do not push, merge, force-push, or delete branches.

---

### Task 1: Language Contract and Compiled Resources

**Files:**
- Create: `CornerPet/Localization/L10n.swift`
- Create: `CornerPet/Localization/AppLocaleScope.swift`
- Create: `CornerPet/Localization/Localizable.xcstrings`
- Create: `CornerPetTests/LocalizationTests.swift`
- Modify: `CornerPet/Settings/AppSettings.swift`
- Modify: `CornerPet/App/AppDelegate.swift`
- Modify: `CornerPetTests/AppConfigurationTests.swift`
- Modify: `CornerPetTests/AppSettingsTests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `AppLanguage.locale: Locale`, `AppLocaleScope<Content>`, typed `L10n` resources, `L10n.localized(_:locale:)`, `AppLaunchOptions.languageOverride`.
- Consumes: existing `AppSettings.language` persistence and UI-test master gate.

- [ ] **Step 1: Write the failing language and resource tests**

Add tests that assert:

```swift
XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
XCTAssertEqual(AppLanguage.simplifiedChinese.locale.identifier, "zh-Hans")
XCTAssertEqual(
    AppLaunchOptions(arguments: [
        "CornerPet", "--cornerpet-ui-testing", "--cornerpet-ui-language=en"
    ]).languageOverride,
    .english
)
XCTAssertNil(AppLaunchOptions(arguments: [
    "CornerPet", "--cornerpet-ui-language=zh-Hans"
]).languageOverride)
```

`LocalizationTests` must load each `L10n.allKeys` entry through the compiled product bundle for `en` and `zh-Hans`, assert the result is non-empty, and assert it differs from the key.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
CORNERPET_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project CornerPet.xcodeproj -scheme CornerPet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CornerPetTests/AppConfigurationTests \
  -only-testing:CornerPetTests/AppSettingsTests \
  -only-testing:CornerPetTests/LocalizationTests
```

Expected: compile failure for the new locale/resource interfaces or missing catalog values, not a project parse error.

- [ ] **Step 3: Add the minimum locale and catalog implementation**

Implement `AppLanguage.locale`, a generic locale-scoping view whose `body` reads `settings.language.locale`, the gated launch argument, typed resource constants, and both catalog translations. Add the two localization Swift files to the app Sources phase, the catalog to app Resources, and the test file to unit-test Sources.

- [ ] **Step 4: Apply the UI-test override before host construction**

In `AppDelegate.init`, after `AppSettings` is constructed and before factories install content:

```swift
if let languageOverride = launchOptions.languageOverride {
    appSettings.setLanguage(languageOverride)
}
```

Do not mutate `AppleLanguages`, global defaults, or production launch state.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Step 2 command. Expected: every selected test passes and compiled resources return real English/Chinese copy.

- [ ] **Step 6: Inspect and commit the increment**

Run `git diff --check`, inspect staged resource/project membership, then commit:

```bash
git commit -m "feat: add runtime localization foundation"
```

### Task 2: Localize App, Capture, Library, Settings, and Error Surfaces

**Files:**
- Modify: `CornerPet/App/CornerPetApp.swift`
- Modify: `CornerPet/App/AppDelegate.swift`
- Modify: `CornerPet/Capture/CaptureCompositionRoot.swift`
- Modify: `CornerPet/Capture/CaptureDestination.swift`
- Modify: `CornerPet/Capture/CapturePanelView.swift`
- Modify: `CornerPet/Capture/CaptureHeaderView.swift`
- Modify: `CornerPet/Capture/CaptureNavigationBar.swift`
- Modify: `CornerPet/Capture/CaptureTextEditor.swift`
- Modify: `CornerPet/Capture/InboxView.swift`
- Modify: `CornerPet/Capture/ItemRow.swift`
- Modify: `CornerPet/Capture/ArchiveView.swift`
- Modify: `CornerPet/Capture/ArchiveItemRow.swift`
- Modify: `CornerPet/Capture/FavoritesView.swift`
- Modify: `CornerPet/Capture/InlineItemEditor.swift`
- Modify: `CornerPet/Capture/CaptureViewModel.swift`
- Modify: `CornerPet/Settings/CornerPetSettingsView.swift`
- Modify: `CornerPet/Settings/LaunchAtLoginController.swift`
- Modify: `CornerPet/Localization/L10n.swift`
- Modify: `CornerPet/Localization/Localizable.xcstrings`
- Modify: affected unit tests

**Interfaces:**
- Consumes: Task 1 `L10n` resources and `AppLocaleScope`.
- Produces: localized, live-updating app/settings/capture/library copy and localized AppKit accessibility labels.

- [ ] **Step 1: Add failing behavioral tests for localized errors and AppKit labels**

Replace the old dual-message assertion with locale-specific expectations:

```swift
XCTAssertEqual(L10n.localized(.captureSaveFailed, locale: Locale(identifier: "en")),
               "Couldn’t save. Your draft is still here—try again.")
XCTAssertEqual(L10n.localized(.captureSaveFailed, locale: Locale(identifier: "zh-Hans")),
               "无法保存。草稿仍在，请重试。")
```

Add hosted-view tests that set an English locale, then a Chinese locale, call `updateNSView`, and assert the native capture/inline text views expose the correct localized accessibility label and placeholder.

- [ ] **Step 2: Run the focused tests and verify RED**

Select `CaptureViewModelTests`, `CaptureLayoutTests`, and the new localization tests. Expected: the old bilingual properties/labels do not satisfy the locale-specific contract.

- [ ] **Step 3: Replace inline bilingual strings feature by feature**

Use `Text(L10n...)`, localized label content, and `L10n.localized(_:locale:)` for AppKit. Keep all existing identifiers unchanged. Remove `CaptureSaveError.englishMessage` and `.chineseMessage` only after all consumers and tests use the single localized resource.

- [ ] **Step 4: Propagate locale through every host**

Wrap capture composition, persistence error, reminder content, and the settings scene in the settings-backed locale scope. Ensure `CaptureTextEditor` and `InlineItemEditor` read `@Environment(\.locale)` and refresh native accessibility properties from `updateNSView`.

- [ ] **Step 5: Make launch-at-login failures actionable**

Expose a stable localized error resource for registration/unregistration failure and, if retained, present the system diagnostic only as secondary selectable detail. Do not use `localizedDescription` as the sole UI copy.

- [ ] **Step 6: Verify the focused suite and build**

Run selected unit tests and an arm64 Debug build. Expected: no mixed UI contract remains in changed tests, the app compiles against macOS 14, and all selected tests pass.

- [ ] **Step 7: Inspect and commit the increment**

Run `git diff --check`, scan the product Swift files for the old `"中文 / English"` UI pattern, inspect the staged diff, then commit:

```bash
git commit -m "feat: localize CornerPet interface copy"
```

### Task 3: VoiceOver and Reduced-Motion Baseline

**Files:**
- Create: `CornerPet/Reminder/ReminderAnimationPolicy.swift`
- Create: `CornerPetTests/ReminderAnimationPolicyTests.swift`
- Modify: `CornerPet/Reminder/CatReminderView.swift`
- Modify: `CornerPet/Capture/ItemRow.swift`
- Modify: `CornerPet/Capture/ArchiveItemRow.swift`
- Modify: `CornerPet/Capture/FavoritesView.swift`
- Modify: `CornerPet/Capture/CaptureNavigationBar.swift`
- Modify: `CornerPet/Capture/InlineItemEditor.swift`
- Modify: `CornerPet/Settings/CornerPetSettingsView.swift`
- Modify: `CornerPet/Localization/L10n.swift`
- Modify: `CornerPet/Localization/Localizable.xcstrings`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `ReminderAnimationPolicy` with reduced-motion duration/transform behavior and named localized edit actions.
- Consumes: `PanelAnimator.reducedMotionDuration` and Task 2 localization resources.

- [ ] **Step 1: Write the failing reminder policy tests**

Assert reduced motion uses exactly 0.120 seconds, scale 1, offset 0, and no bounce; assert normal motion retains 0.42-second spring inputs and the existing 0.9/±10 initial transform.

- [ ] **Step 2: Run focused motion tests and verify RED**

Run the new policy tests plus `PanelAnimatorTests`. Expected: the policy type is missing while the existing panel 120 ms/no-overshoot regression remains green.

- [ ] **Step 3: Implement and consume the policy**

Move only the reminder decision values into `ReminderAnimationPolicy`; keep the cat drawing unchanged. Reduced motion must animate opacity only using `PanelAnimator.reducedMotionDuration`.

- [ ] **Step 4: Close concrete VoiceOver gaps**

Add localized named edit actions to item text, localized selected navigation values, identifiers for Task 13 settings actions/error text, and appropriate hidden decoration. Replace affected `.caption2` copy with `.caption` where it does not change structure.

- [ ] **Step 5: Run focused unit tests and build**

Run motion, panel, layout, and settings tests, followed by Debug build. Expected: all selected tests and build pass.

- [ ] **Step 6: Inspect and commit the increment**

Review the changed SwiftUI files against `swiftui-pro` accessibility/design/view guidance and commit:

```bash
git commit -m "feat: establish VoiceOver and reduced motion baseline"
```

### Task 4: Bilingual and Accessibility UI Automation

**Files:**
- Create: `CornerPetUITests/LocalizationAccessibilityUITests.swift`
- Modify: `CornerPetUITests/CaptureFlowUITests.swift`
- Modify: `CornerPetUITests/LibraryFlowUITests.swift`
- Modify: `CornerPetUITests/PinningFlowUITests.swift`
- Modify: `CornerPetUITests/ReminderFlowUITests.swift`
- Modify: `CornerPet.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: gated `--cornerpet-ui-language` and stable identifiers.
- Produces: deterministic `en`/`zh-Hans` launch coverage and accessibility interaction regression coverage.

- [ ] **Step 1: Add the failing English and Chinese UI tests**

Launch with a fresh in-memory store and explicit language. Assert by identifier that:

- `capture.input`, `capture.pin`, all navigation actions, search fields, settings language picker, and reminder buttons have non-empty localized labels;
- English labels equal the English contract and do not contain the old slash-paired copy;
- Chinese labels equal the Chinese contract and do not expose catalog keys;
- the fixed panel's tested controls have non-empty frames and are hittable/enabled where expected.

- [ ] **Step 2: Add a live language-switch UI path**

Open settings through `nav.settings`, change `settings.language` to Simplified Chinese using the native picker, return focus to the capture panel, and assert `capture.pin` changes from `Pin` to `置顶` without relaunch.

- [ ] **Step 3: Verify RED through the protected runner**

Run the focused new UI class with the Task 12.5 input-source guard. Expected: at least the missing live propagation/accessibility behavior fails as a reached product assertion; infrastructure failures must be classified separately.

- [ ] **Step 4: Update earlier UI contracts to deterministic language**

Add an explicit English UI-test language to shared launch arrays and replace only assertions that depended on old bilingual labels. Keep stable identifiers and all existing flow assertions.

- [ ] **Step 5: Verify the focused UI class and the complete UI suite**

Run the focused localization/accessibility class, then `Scripts/run-ui-tests.sh`. Preserve `.xcresult`, log, classification, executed count, failures, skips, and language assertions.

- [ ] **Step 6: Inspect and commit the increment**

Inspect test behavior rather than source-string presence, then commit:

```bash
git commit -m "test: cover bilingual and accessible UI contracts"
```

### Task 5: Final Verification, Evidence, and Review

**Files:**
- Create: `docs/verification/task-13-verification.md`
- Modify: `tasks/plan.md`
- Modify: `tasks/todo.md`
- Modify only if a Required finding demands it: Task 13 product/test files

**Interfaces:**
- Consumes: all Task 13 commits and Task 12.5 verification workflow.
- Produces: auditable Task 13 evidence, accurate remaining manual gates, and merge-readiness status.

- [ ] **Step 1: Run full unit tests from the final tree**

Run `xcodebuild test` selecting `CornerPetTests`. Record executed, failed, skipped, warning, and result-bundle counts.

- [ ] **Step 2: Run the guarded full UI suite**

Run `Scripts/run-ui-tests.sh` in an exclusive desktop or the accepted isolated VM. Record runner classification, exact executed/failed/skipped counts, input-source restoration, log, and result bundle. Do not claim a pass for an infrastructure classification.

- [ ] **Step 3: Run build and analysis gates**

Run a clean arm64 Debug build, `xcodebuild analyze`, and `Scripts/release.sh local-build`. Confirm the Release app remains arm64, version 0.1.0 (1), bundle ID `com.jack.CornerPet`, `LSUIElement=true`, and unsigned/non-distribution status is stated accurately.

- [ ] **Step 4: Run static and resource checks**

Run `git diff --check`, validate the project with `xcodebuild -list`, inspect compiled `.lproj` resources, scan changed user-facing Swift for raw catalog keys/old slash-paired copy, scan the diff for credential-like names, and confirm no dependency or SwiftData schema changes.

- [ ] **Step 5: Perform an independent five-axis review**

Review tests first, then implementation for correctness, readability, architecture, security/privacy, and performance. Apply the full `swiftui-pro` checklist to changed SwiftUI/AppKit bridge files. Categorize findings as Critical, Required, Optional, or Nit; fix and freshly reverify all Critical/Required findings.

- [ ] **Step 6: Record evidence and update task status**

Write exact commands/results and separate automated passes from manual/not-executed checks. Mark Task 13 complete only if every automated Task 13 gate is green; leave Task 14 unchecked.

- [ ] **Step 7: Commit the verification record**

Inspect the final staged diff and commit:

```bash
git commit -m "docs: record Task 13 verification evidence"
```

- [ ] **Step 8: Final branch audit**

Report branch, base, commit list, clean/dirty status, unpushed state, verification evidence, review verdict, and the exact real-device/manual checks still required. Do not push, merge, or delete any branch.

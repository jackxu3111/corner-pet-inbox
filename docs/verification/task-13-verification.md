# CornerPet Task 13 Verification

- **Date:** 2026-08-29
- **Base:** `8711a8b` (`codex/cornerpet-task-12-5`)
- **Branch:** `codex/cornerpet-task-13`
- **Tested implementation:** `8066f6adbf1758b93609af12f68193207d88c12a`
**Result:** Task 13's automated bilingual, accessibility, and reduced-motion baseline passes. Task 14 and the session-, hardware-, and perception-dependent manual matrix remain open.

## Delivered Baseline

- Complete English and Simplified Chinese resources through one 82-key String Catalog and typed `L10n` resources.
- System-language default plus persisted English/Simplified Chinese override, with live propagation to settings, capture, reminder, persistence-error, and AppKit-backed editor surfaces.
- A deterministic language launch override that is ignored unless the existing UI-test master gate is present.
- Localized VoiceOver labels/help, selected navigation values, named item-edit actions, hidden decoration, and actionable retry/dismiss error controls while preserving stable automation identifiers.
- A testable reminder motion policy: reduced motion is exactly 120 ms, opacity-only, scale `1`, offset `0`, and has no bounce; normal motion retains the existing spring behavior.
- No SwiftData schema, dependency, network, analytics, updater, or product-layout expansion.

## Automated Verification

| Gate | Result | Evidence |
|---|---:|---|
| Final unit suite in isolated VM | **354 passed, 0 failed, 0 skipped** | `8066f6a-unit-tests/CornerPetTests.xcresult`; independent `xcresulttool` summary reports 354 total and no runtime warnings |
| Final guarded UI suite in isolated VM | **25 passed, 0 failed, 0 skipped**; runner classification `passed` | `8066f6a-20260829-053617/CornerPetUITests.xcresult`; includes 4 bilingual/accessibility tests |
| Focused final localization/accessibility UI suite | **4 passed, 0 failed** | English, Simplified Chinese, live language switching through SwiftUI and AppKit, reminder actions, action audit, frames, and hittability |
| UI runner contract suite | **13 passed** | `/tmp/cornerpet-task13-ui-runner-contract.log` |
| Release workflow contract suite | **11 passed** | `/tmp/cornerpet-task13-release-contract.log` |
| UI `build-for-testing` | **TEST BUILD SUCCEEDED** | `/tmp/cornerpet-task13-ui-build-strengthened.log` at `acaad48`; the final `8066f6a` product and tests were then rebuilt by the complete guarded run |
| Clean arm64 Debug build | **BUILD SUCCEEDED** | `/tmp/cornerpet-task13-debug-8066f6a.log` |
| Static analysis | **ANALYZE SUCCEEDED** | `/tmp/cornerpet-task13-analyze-8066f6a.log` |
| Release workflow `local-build` | **BUILD SUCCEEDED** | `/tmp/cornerpet-task13-release-8066f6a.log` |
| Project, resource, and diff checks | **Passed** | `xcodebuild -list`, `git diff --check`, catalog/compiled-resource checks, raw-copy scan, dependency/schema/credential diff review |

The final unit and UI result bundles are retained outside the Git worktree at:

- `/Users/jack/.codex/vm/CornerPet-UI-Test/exchange/task-13-evidence/8066f6a-unit-tests/`
- `/Users/jack/.codex/vm/CornerPet-UI-Test/exchange/task-13-evidence/8066f6a-20260829-053617/`

The full unit and UI suites both ran from the clean guest branch `codex/cornerpet-task-13` at `8066f6a`. Clean Debug, Release, static analysis, and artifact inspection also ran against that exact implementation commit.

## Release Artifact Inspection

`Scripts/release.sh local-build` produced an unsigned local artifact with:

- Mach-O architecture: `arm64`
- Version: `0.1.0` (`1`)
- Bundle identifier: `com.jack.CornerPet`
- `LSUIElement`: `true`
- Signature: ad hoc; `TeamIdentifier=not set`
- Compiled resources: `en.lproj` 82 entries and `zh-Hans.lproj` 82 entries, with identical non-empty key sets

This is a successful local Release build, not a Developer ID-signed or notarized distribution artifact. Distribution credentials and notarization remain outside Task 13.

## Static and Scope Review

- Source catalog: 82 keys; English missing/empty values: 0; Simplified Chinese missing/empty values: 0.
- The only retained slash-paired identity is the approved external display name `CornerPet / 角落灵感箱`; the visual brand word `CornerPet` remains intentionally stable.
- No package/dependency manifest changed.
- No SwiftData model or versioned schema changed.
- No credential-like material was introduced; matching scan terms occur only in verification prose.
- `git diff --check 8711a8b..8066f6a` and Xcode project discovery both pass.

## Environment Classification and Warnings

The host desktop could build the app and tests but could not reliably launch XCTest/UI automation: the host unit run stalled before the first test, and two guarded host UI attempts timed out while initializing automation before reaching a product assertion. Per the Task 12.5 runner contract, these are environment failures rather than product passes or failures. The accepted final unit/UI evidence therefore comes from the dedicated clean arm64 VM with an active Aqua session and only the ABC input source.

The final UI result contains one existing QoS priority-inversion runtime warning in `LibraryFlowUITests`; it has no test failure and is retained as Task 14 toolchain/test-harness debt. Xcode 27 also reports existing Swift 6 Sendable-capture warnings in unchanged test fixtures and the harmless App Intents metadata-extraction warning. No Task 13 product-code warning or analyzer finding was reported.

The protected host runner changed the host input source from Doubao to ABC. Its restoration helper returned success, but the foreground input source immediately switched back to ABC. Current host state is still ABC; Jack must manually select Doubao again. This does not affect the isolated VM results.

## Independent Review

Independent read-only review covered the final implementation and test tree across correctness, readability, architecture, privacy/security, performance, SwiftUI, AppKit bridging, and acceptance coverage. The first pass found two Required issues: launch-language overrides persisted to shared preferences, and the two clear-search icon buttons lacked localized help. Commit `8066f6a` separated transient from persisted language mutation, added a RED→GREEN preference regression, added both localized help modifiers, and adopted the reviewer's optional bilingual selected-value UI assertions. Re-review of `acaad48..8066f6a` reports **no Critical, Required, Optional, or Nit findings remaining**.

## Manual Acceptance Still Required

Automated gates cannot establish speech quality, perception, real input-method behavior, or physical session/display integration. Before a release candidate is accepted, run:

1. VoiceOver reading order, focus recovery, rotor discovery, and the localized named edit action in both languages.
2. English and Simplified Chinese clipping checks at common text sizes and the largest macOS accessibility sizes.
3. Reduce Motion observation for capture open, close, reversal, and reminder presentation at all four corners; confirm the reduced path is opacity-only and visually completes in 120 ms.
4. Live Chinese IME composition and submission with Doubao or the intended production IME.
5. Finder/Safari/Xcode full-screen Spaces, physical multi-display placement and display disconnect recovery, pinned drag/resize, and unpin/retrigger behavior.
6. Sleep/wake reminder behavior plus real login, logout, restart, and hidden login launch.

Task 14 remains responsible for privacy-safe local metrics, extended compatibility/QA, Developer ID/notarization gates when credentials are available, and the seven-day release-candidate record.

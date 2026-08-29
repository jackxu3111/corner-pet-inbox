# CornerPet Task 13 Localization and Accessibility Design

**Date:** 2026-08-29
**Base:** `8711a8b` from `codex/cornerpet-task-12-5`
**Implementation branch:** `codex/cornerpet-task-13`
**Status:** Approved for execution by Jack's Task 13 delegation

## Context

CornerPet currently exposes a persisted language preference, but the preference does not affect the UI. Most visible copy is rendered as a Chinese/English pair in one string, AppKit text views use fixed bilingual accessibility labels, the reminder's reduced-motion fade lasts 160 ms, and several row interactions are discoverable only through a mouse double-click.

Task 13 turns the existing placeholder behavior into the final MVP baseline. It does not redesign the capture panel, settings page, library rows, or cat; it does not add cloud sync, analytics, an updater, dependencies, or new product workflows.

## Goals

1. Provide complete Simplified Chinese and English UI resources.
2. Follow the macOS language by default and allow a persisted manual override.
3. Apply a changed language to the settings window, capture panel, reminder panel, menus, help, error copy, and AppKit accessibility text without restarting.
4. Make all task-scope controls discoverable and operable with VoiceOver while preserving stable automation identifiers.
5. Make reduced-motion presentation converge in 120 ms without spring overshoot or spatial movement.
6. Protect the behavior with unit and UI automation, then run the full release-candidate engineering gates that are available without distribution credentials.

## Non-goals

- No visual redesign, new pet artwork, new window layout, or new navigation.
- No additional languages beyond `en` and `zh-Hans`.
- No remote services, telemetry, automatic updates, or third-party packages.
- No Task 14 privacy metrics, seven-day product validation, or Developer ID/notarization work.
- No attempt to automate session-dependent physical-display, sleep/wake, live IME composition, logout, or real VoiceOver speech-quality checks.

## Acceptance Contract

### Language behavior

- A fresh install uses `AppLanguage.system` and resolves through `Locale.autoupdatingCurrent`.
- Selecting English or Simplified Chinese persists the exact override and updates every live SwiftUI host.
- AppKit-backed capture and inline editors refresh their label and placeholder from the same effective locale.
- UI-test language overrides are accepted only behind `--cornerpet-ui-testing`; production arguments cannot mutate language.
- English and Chinese surfaces show one language at a time. The stable external product name `CornerPet / 角落灵感箱` remains unchanged because it is a confirmed product identity, not interface copy.

### Resource completeness

- `CornerPet/Localization/Localizable.xcstrings` is the single translation source.
- `CornerPet/Localization/L10n.swift` provides typed `LocalizedStringResource` constants grouped by feature.
- Both catalog localizations have non-empty values for every shipped key.
- Runtime resource tests load the compiled product resources in `en` and `zh-Hans` and fail if lookup returns a raw key.

### Accessibility

- Every interactive control touched by Task 13 keeps or receives a stable accessibility identifier.
- Icon-only buttons expose localized labels and help text; decorative images remain hidden.
- Navigation exposes a localized selected value.
- Item text retains mouse double-click editing and adds a named accessibility edit action.
- Native text views expose localized labels and capture placeholder text.
- Error banners expose understandable localized text and actionable retry/dismiss controls.
- Very small `.caption2` labels in the Task 13 surfaces move to `.caption` where layout permits.

### Motion

- Capture-panel reduced motion remains exactly 120 ms and never exceeds its final scale/frame.
- Reminder reduced motion uses a 120 ms opacity-only transition; its cat scale and offset are already final from the first frame.
- The normal spring reminder and normal corner-growth animation remain unchanged.

### Verification

- Focused red/green tests cover language argument gating, locale resolution, compiled resource completeness, and reminder motion policy.
- `LocalizationUITests` launches both languages and checks visible copy plus localized accessibility labels by stable identifier.
- Accessibility UI coverage exercises the edit action contract and verifies key controls are enabled and labeled.
- Existing UI tests stop depending on mixed bilingual labels and run under a deterministic language.
- Complete unit tests, guarded UI tests, Debug build, unsigned arm64 Release build, static analysis, project/resource scans, and `git diff --check` pass with fresh evidence.

## Architecture

### Native localization resources

Use an Xcode String Catalog rather than a hand-built dictionary. `L10n` owns typed resource constants, not translated values. SwiftUI renders those resources using the locale environment. AppKit bridge views render the same resources with `String(localized:locale:)` whenever SwiftUI updates their representable.

This keeps fallback behavior, plural/date formatting, and future resource tooling within Foundation and SwiftUI. It also makes missing resources observable in the compiled app bundle.

### Runtime locale propagation

`AppLanguage` maps to an effective locale:

- `.system` → `.autoupdatingCurrent`
- `.simplifiedChinese` → `Locale(identifier: "zh-Hans")`
- `.english` → `Locale(identifier: "en")`

An `AppLocaleScope` view reads the observable `AppSettings.language` inside `body` and injects the effective locale. It wraps the capture composition and reminder content. The settings scene receives the same locale at scene level so settings and command labels update from the same source of truth.

No process-wide `AppleLanguages` mutation, bundle swizzling, relaunch, or duplicated localization state is introduced.

### Test-only language override

`AppLaunchOptions` parses `--cornerpet-ui-language=en|zh-Hans|system` only when the master UI-test flag is present. `AppDelegate` applies the override before hosted views are installed. This produces deterministic UI tests without changing production defaults or shared user preferences.

### Accessibility remediation

Task 13 localizes existing labels and fills specific observable gaps instead of restructuring screens:

- add labels/help for every icon-only action;
- add identifiers to Task 13 settings actions and messages;
- add an accessibility edit action to item text while preserving double-click for pointer users;
- keep all data text as real accessible text;
- keep decoration hidden and avoid color-only status communication;
- preserve existing row/list/panel identifiers so earlier UI automation remains stable.

### Reduced-motion policy

Extract the reminder presentation decision into a small value policy that can be unit-tested. The policy yields initial transform values and a duration. Reduced motion starts at the final scale/offset and fades over `PanelAnimator.reducedMotionDuration`; normal motion retains the current spring, scale, and offset.

## Error Handling

- Persistence, loading, archive, favorite, edit, delete, and launch-at-login errors use concise localized recovery copy.
- The underlying error is not exposed as the only user message; launch-at-login retains diagnostic text only as secondary selectable detail if it materially helps troubleshooting.
- Missing catalog values fail automated tests rather than silently shipping raw keys.
- Invalid UI-test language arguments are ignored and fall back to the persisted/system choice.

## Data and Privacy

Language remains a non-sensitive `UserDefaults` value under the existing key. No content, accessibility state, locale, or error is transmitted. The SwiftData schema and user content are untouched.

## Risks and Mitigations

- **Runtime language changes fail to reach an existing hosting view:** the observable settings object is read inside `AppLocaleScope.body`; UI tests exercise both startup override and live settings selection.
- **AppKit labels stay stale:** each representable reads `EnvironmentValues.locale` and refreshes native accessibility properties in `updateNSView`.
- **A catalog key ships untranslated:** compiled-resource tests enumerate every declared key for both localizations.
- **Localized copy truncates in the compact panel:** UI tests inspect element frames/hittability at the fixed 360×450 baseline; long settings guidance remains vertically flowing.
- **Accessibility work changes mouse behavior:** existing pointer/UI flows remain in the full regression suite, and the new action is additive.
- **UI automation depends on the active desktop:** use the protected runner and, where necessary, the already-approved isolated VM workflow from Task 12.5.

## Manual Acceptance Remaining After Automation

- VoiceOver reading order, rotor/action naming, and focus recovery in the real app.
- English and Chinese clipping at common macOS text sizes, including the largest accessibility sizes.
- Reduce Motion observation for panel open/close/reversal and all four reminder corners.
- Live Chinese IME composition, full-screen Spaces, physical multi-display placement, drag/resize, sleep/wake, and login/restart checks retained from Task 12.5.

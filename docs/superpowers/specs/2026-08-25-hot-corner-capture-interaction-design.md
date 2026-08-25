# CornerPet Hot-Corner Capture Interaction Design

## Status

Design decisions and this written specification were approved by Jack on 2026-08-25. This document defines the MVP interaction contract for hot-corner triggering, capture-panel behavior, drafts, item operations, pinning, full-screen spaces, multiple displays, animation, errors, and verification.

## Product Intent

CornerPet lets a Mac user hand off a sudden thought without leaving the current application. The primary interaction must feel spatially stable, require no classification before capture, preserve unfinished text, and return the user to the previous task quickly.

The core promise is:

> Move to a chosen screen corner, record a thought, press Return, and trust that the thought is stored locally.

## MVP Platform

- Native macOS application.
- Minimum version: macOS 14 Sonoma.
- Architecture: Apple Silicon arm64 only.
- UI languages: Simplified Chinese and English.
- Local operation only; no account, cloud sync, or network dependency.

## Chosen Design

The selected design combines:

- A narrow, invisible L-shaped trigger along the selected screen edges.
- A capture-first panel with the input fixed at the top.
- A corner-growth animation rather than a sliding notification.
- A single shared inbox across displays.
- A distinction between an open floating panel and a pinned movable panel.

Rejected alternatives:

- A large L-shaped trigger region: easier to hit but too likely to conflict with menus and window controls.
- An input-only popup: minimal, but adds another action before reviewing pending thoughts.
- A list-first layout: encourages review before capture and interrupts the user's current train of thought.
- A panel sliding from outside the screen: reads as a notification rather than an object that lives in the corner.
- Cross-platform wrappers: add background cost and still require native macOS window integration.

## Terminology

- **Trigger corner:** One of top-left, top-right, bottom-left, or bottom-right selected in settings.
- **Trigger zone:** The invisible L-shaped edge region at the trigger corner.
- **Draft:** Text typed into the capture input that has not been submitted with Return.
- **Formal item:** A locally persisted inbox record created after successful submission.
- **Open panel:** A visible panel above ordinary applications that is still governed by auto-hide rules.
- **Pinned panel:** A visible panel above ordinary applications that does not auto-hide and may be moved or resized.
- **Pointer inside:** The global pointer location lies inside the current panel frame.

## Interaction Constants

| Parameter | MVP value |
|---|---:|
| Trigger arm length | 43 pt per edge, approximately 1.5 cm |
| Trigger thickness | 6 pt, approximately 2 mm |
| Fast dwell preset | 500 ms |
| Standard dwell preset | 600 ms |
| Conservative dwell preset | 700 ms |
| Default dwell preset | Standard, 600 ms |
| Empty-panel exit debounce | 120 ms |
| Post-close trigger debounce | 80 ms |
| Default panel size | 320 × 400 pt |
| Minimum pinned size | 280 × 320 pt |
| Maximum pinned size | 480 × 640 pt |
| Open animation | 260 ms |
| Close animation | 180 ms |
| Reduced-motion transition | 120 ms fade/scale |
| Archive undo duration | 5 seconds |
| Reminder snooze duration | 10 minutes |

The centimeter values are approximate. macOS behavior is defined in logical points so it remains deterministic across display scaling modes.

## Trigger-Zone Geometry

The trigger zone consists of two 43 × 6 pt rectangles that share the selected corner:

- At top-left, one rectangle runs right along the top edge and the other runs down along the left edge.
- At top-right, the geometry mirrors horizontally.
- At bottom-left, the geometry mirrors vertically.
- At bottom-right, it mirrors both horizontally and vertically.

The zone:

- Is completely invisible.
- Touches the physical screen frame.
- Uses the full screen frame for detection, not the visible content frame.
- Uses the visible safe area for panel placement.
- Is recalculated whenever displays connect, disconnect, move, or change scaling.

## Trigger Timing

1. The pointer enters either arm of the L-shaped trigger zone.
2. The pointer may move within the combined L shape without resetting the dwell timer.
3. Leaving the combined L shape before the selected dwell duration cancels the candidate.
4. Re-entering starts a new dwell timer.
5. Reaching the dwell duration requests panel presentation exactly once.
6. A fully closed panel has an 80 ms debounce before a new dwell candidate may begin.
7. If the panel is still closing when the zone triggers again, the close animation reverses from its current progress; it does not snap closed or wait for a fixed cooldown.

The dwell setting exposes only three presets: 500, 600, and 700 ms. The MVP does not expose a continuous slider.

## Panel Placement and Size

Default behavior:

- The panel is 320 × 400 pt.
- It is placed eight points inside the safe visible area of the selected corner.
- Its animation origin matches the selected corner.
- It does not cover the full desktop or become a conventional main application window.

Unpinned:

- The panel is attached to the selected corner.
- It cannot be dragged or resized.
- It appears above ordinary application windows.

Pinned:

- The panel remains above ordinary application windows.
- It may be freely moved on the current display.
- It may be resized between 280 × 320 and 480 × 640 pt.
- Its last pinned size is persisted.
- Moving it does not change the configured trigger corner.

Unpinning:

- The panel returns to the configured corner with the same spring language as opening.
- It retains the user's last valid size.
- If a draft or active edit exists, it stays open at the corner.
- If no draft or active edit exists and the pointer is outside, it closes after returning.

## Panel Layout

The selected layout is capture-first:

1. Header:
   - Minimal cat status.
   - CornerPet name.
   - Pin toggle.
2. Capture input:
   - Always at the top.
   - Automatically receives focus after presentation.
   - Starts at one line.
   - Expands to five visible lines.
   - Scrolls internally beyond five lines.
3. Inbox list:
   - Displays all active items.
   - Sorts newest first.
   - Scrolls independently from the header, input, and navigation.
4. Bottom navigation:
   - Inbox.
   - Favorites.
   - Archive.
   - Settings.

There is no artificial text-length limit in the MVP. Long text remains locally stored and scrolls within the input or row detail.

## Draft Lifecycle

Draft text is a singleton separate from formal items.

- Typing the first character enters draft-locked state.
- Draft changes are persisted locally with a short write debounce and are flushed when the panel closes, the app resigns activity, or the app terminates normally.
- Pointer exit does not close the panel while a draft is active.
- Clicking another application's window closes the unpinned panel but does not submit or clear the draft.
- Escape closes the unpinned panel but does not submit or clear the draft.
- The next presentation restores the draft and places the insertion point at the end.
- App restart and Mac restart restore the draft.
- Empty draft content is never stored as a formal item.
- Duplicate formal items are allowed.
- Only successful Return submission clears the draft.

No shortcut clears a draft. The input exposes a clear button. Clearing a non-empty draft requires confirmation.

## Submission with Return

Return means submit the current draft as one formal item.

1. Normalize only leading and trailing whitespace.
2. Reject an empty result without creating an item.
3. Ask ItemStore to persist the formal inbox item.
4. Clear the draft only after persistence succeeds.
5. Insert the new item at the top of the visible inbox list.
6. Evaluate current pointer position:
   - Pointer inside: keep the panel open and focus the empty capture input.
   - Pointer outside and unpinned: close the panel.
   - Pinned: remain open regardless of pointer position.

Shift-Return inserts a newline instead of submitting.

## Auto-Hide Rules

An unpinned panel with no draft and no active item edit:

- Starts a 120 ms close debounce when the pointer leaves its frame.
- Cancels the close if the pointer re-enters before the debounce ends.
- Closes after the debounce if the pointer stays outside.

An unpinned panel with a new-item draft:

- Does not close merely because the pointer leaves.
- Closes on Escape while preserving the draft.
- Closes when another application receives a click and preserves the draft.

An unpinned panel with an active existing-item edit:

- Does not close merely because the pointer leaves.
- Escape cancels the edit, restores the original text, and keeps the panel open.
- Clicking another application attempts to save the edit, then closes only if the save succeeds.
- A failed edit save keeps the panel and editor open.

A pinned panel never auto-hides because of pointer exit or external focus.

The hidden panel must be removed from the window list so no transparent surface intercepts clicks.

## Keyboard Contract

| Shortcut | Behavior |
|---|---|
| Return | Submit a new draft or confirm an existing-item edit |
| Shift-Return | Insert a newline |
| Escape | Close while preserving new draft; cancel existing-item edit |
| Command-Shift-P | Toggle pinning |
| Command-F | Focus search in Archive or Favorites |

The MVP adds no shortcut for deleting or clearing content.

## Formal Item Operations

Each inbox row includes:

- An unchecked completion box.
- Item text.
- Favorite and delete actions revealed on hover.

Completion:

- Moves the item to Archive.
- Removes it from Inbox.
- Shows an “Archived · Undo” action for five seconds.
- Undo moves it back to Inbox.

Favorite:

- Moves the item to Favorites.
- Removes it from Inbox.
- Favorites is one flat searchable list.
- Removing Favorite returns the item to Inbox.

Delete:

- Requires explicit destructive confirmation.
- Deletes permanently after confirmation.
- Does not create a second recycle bin.

Archive:

- Sorts newest moved item first.
- Supports text search.
- Does not expire records automatically.
- Permanent deletion requires confirmation.

## Editing Formal Items

- Double-clicking item text enters inline edit.
- The original value remains available until the edit finishes.
- Return saves the edit.
- Shift-Return inserts a newline.
- Escape cancels the edit and restores the original value.
- Clicking elsewhere saves the edit.
- While editing, completion, favorite, and deletion actions are disabled.
- Saving updates updatedAt but preserves createdAt.
- The MVP stores no edit-version history.

If an edit save fails, the editor remains open with the changed text and displays the same persistent error treatment as new-item submission.

## Error Handling

New-item save failure:

- Does not clear the draft.
- Does not close the panel.
- Displays a compact red rounded error panel in the middle area without covering the input.
- Shows “Save failed. Try again.” and a Retry action.
- Remains visible until retry, successful save, or explicit dismissal.
- Dismissing the error does not clear the draft.

List-load failure:

- Does not disable the capture input.
- Replaces only the list area with an error and Retry action.
- Leaves the draft path operational.

Permanent-delete failure:

- Leaves the item in its current list.
- Shows an error without claiming deletion succeeded.

Errors are localized in Chinese and English. No error path silently discards text.

## Animation

The selected animation is corner growth:

- The panel begins as a small rounded capsule at the selected corner.
- Width and height expand together from that corner.
- The surface has a small, highly damped overshoot.
- Content fades in after the shell begins expanding, so text does not visibly stretch.
- Closing reverses the sequence: content fades, then the shell contracts into the corner.
- Re-triggering during close reverses the active animation from its current progress.
- Other corners use the same animation with a mirrored transform origin.

Opening lasts about 260 ms; closing lasts about 180 ms. Motion must feel responsive rather than decorative.

When Reduce Motion is enabled:

- Do not use spring overshoot.
- Use a 120 ms opacity and subtle scale transition.
- Keep all timing and focus rules otherwise identical.

## Full-Screen and Spaces

- Triggering does not exit full-screen mode.
- Triggering does not switch to a different Space.
- The panel appears above the current full-screen application.
- Closing restores keyboard focus to the previously active application.
- Panel placement respects notches, menu bars, Docks, and safe visible areas.
- The panel participates as a full-screen auxiliary window and is available on the active Space.

Full-screen correctness is a first checkpoint, not final polish.

## Multiple Displays

Settings expose:

- Primary display only, the default.
- All displays.

Rules:

- Every enabled display uses the same configured corner.
- Every display uses the same shared draft and item database.
- Only one panel instance exists.
- When unpinned, the panel appears on the display that triggered it.
- When pinned, it stays on its current display.
- A trigger on another display while pinned brings the existing panel forward without moving it.
- If the pinned display disconnects, the panel moves into the primary display's visible area.
- Display reconnection, rearrangement, or scaling causes immediate trigger-zone recalculation.
- The MVP does not support a different corner per display.

## Hot-Corner Conflict Guidance

CornerPet does not use private APIs to read or modify the user's macOS Hot Corners.

- Onboarding explains that the selected corner may conflict with macOS.
- Settings provides a Hot Corner Help view.
- Instructions guide the user to System Settings → Desktop & Dock → Hot Corners.
- The user may clear the system action or choose a different CornerPet corner.
- CornerPet never changes the system setting automatically.

## Persistence Model

Draft:

- text
- updatedAt

IdeaItem:

- id
- text
- bucket: inbox, archive, or favorite
- createdAt
- updatedAt
- movedAt

Settings:

- triggerCorner
- dwellPreset
- displayScope
- lastPinnedSize
- reminderEnabled
- reminderMinutes
- language
- launchAtLogin preference

Reminder state:

- lastFiredAt
- snoozedUntil

User settings and content remain local.

## Component Boundaries

- **HotCornerGeometry:** Pure construction and hit testing of four rotated L shapes.
- **HotCornerStateMachine:** Dwell, cancellation, rearm, and re-trigger decisions.
- **MouseMonitor:** AppKit adapter for local and global mouse movement.
- **ScreenCoordinator:** Current screens, safe areas, configured display scope, and display-change events.
- **PanelStateMachine:** Hidden, open-empty, draft-locked, item-editing, pinned, error, opening, and closing transitions.
- **PanelController:** NSPanel creation, position, size, level, focus, animation, and focus restoration.
- **DraftStore:** Singleton draft persistence and restoration.
- **ItemStore:** Formal-item persistence, movement, search, update, undo, and permanent deletion.
- **ReminderScheduler:** Daily decision, wake recovery, and snooze.
- **SwiftUI Views:** Render state and send intents; they do not own window or persistence policy.

These boundaries keep macOS system integration separate from product rules and allow deterministic unit tests.

## Data Flow

~~~text
Global/local mouse events
    → ScreenCoordinator selects enabled screens
    → HotCornerGeometry performs hit testing
    → HotCornerStateMachine decides show/reverse/nothing
    → PanelStateMachine changes lifecycle state
    → PanelController places and animates NSPanel

Keyboard input
    → DraftStore persists draft
    → Return asks ItemStore to save a formal item
        → success clears draft and updates list
        → failure retains draft and presents error
    → PanelStateMachine evaluates pointer and pin state
    → PanelController stays open or closes
~~~

## Verification

### Unit Tests

- All four L-shaped geometries and boundary points.
- 500, 600, and 700 ms dwell boundaries.
- Leaving and re-entering the trigger.
- 120 ms exit cancellation.
- 80 ms post-close debounce.
- Reverse during close.
- Every PanelStateMachine transition.
- Draft save, restore, and clear-after-success.
- Inbox, archive, favorite, search, edit, undo, and delete.
- Reminder before/after time, same-day suppression, wake, and snooze.

### Integration Tests

- Return save success and failure.
- Pointer-inside and pointer-outside branches after save.
- Draft recovery after app relaunch.
- Item edit failure keeps edited text visible.
- Display disconnect moves a pinned panel into visible space.
- Full-screen panel appearance does not switch Space.

### UI Tests

- Capture and submission.
- Archive, undo, Favorites, search, edit, and delete confirmation.
- Error presentation and Retry.
- Pin shortcut and button.
- Chinese and English labels.
- Reduced Motion behavior without functional changes.

### Manual Mac Matrix

- Finder, Safari, Xcode, and a full-screen video.
- Normal windows, full-screen apps, Spaces, and Stage Manager.
- Built-in display alone.
- External display left and right.
- Different scaling modes.
- Display disconnect and reconnect.
- Sleep across reminder time.
- Login launch.
- Rapid trigger entry/exit and re-trigger during close.

## First Implementation Gate

Before persistence, archive, Favorites, or cat animation proceeds, a throwaway-quality but representative native prototype must prove:

1. The L-shaped trigger feels intentional at 600 ms.
2. Normal usage does not produce unacceptable false triggers.
3. The panel appears above full-screen applications without switching Space.
4. The input receives focus reliably.
5. Closing restores focus and leaves no invisible click blocker.
6. Continuous close/reopen animation is smooth.

Failure at this gate changes geometry, timing, or window strategy before further scope is built.

## Not Doing in the MVP

- Clipboard history.
- Global keyboard capture.
- Voice capture.
- AI classification or summarization.
- Tags, folders, or knowledge graphs.
- Calendar, timer, Pomodoro, or project management.
- Cloud sync or accounts.
- Multiple simultaneous panels.
- Per-display corner configuration.
- Custom pet library.
- Windows, Intel Mac, mobile, team sharing, store, or billing.

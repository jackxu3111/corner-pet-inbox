# CornerPet Isolated UI Test VM Design

**Date:** 2026-08-29

## Purpose

Create a dedicated macOS virtual machine for CornerPet UI automation so XCUITest can control a guest Aqua session without taking over Jack's host pointer, keyboard focus, or active applications.

The first release gate executed in this environment is Task 12.5. Task 13 may begin only after Task 12.5 passes its complete 21-test guarded UI suite and the verified Task 12.5 history is integrated into `origin/main`.

## Scope

The environment includes:

- VirtualBuddy 2.2 Beta 4 installed through the existing Homebrew installation.
- One VM named `CornerPet-UI-Test` running macOS 27.
- Four virtual CPUs, 8 GiB memory, a 120 GB boot disk, and NAT networking.
- A dedicated local guest account named `cornerpet-test`, with automatic login and Remote Login enabled during provisioning.
- Xcode 27 Beta copied from the host and initialized inside the guest.
- A guest-local clone created from an explicit Git bundle rather than a writable mount of the host repository.
- Test invocation over SSH while the guest account remains logged in to its Aqua session.
- Evidence copied back to a dedicated exchange directory outside the CornerPet Git worktrees.

The environment does not include an Apple Account, iCloud, personal documents, host-wide folder sharing, cloud CI, or changes to CornerPet product behavior.

## Rationale

Apple's Virtualization framework supports installing and running macOS guests on Apple silicon. VirtualBuddy provides a maintained interface over that framework, restore-image discovery, guest folder support, and VM management.

VirtualBuddy 2.2 Beta 4 is selected instead of stable 2.1 because its macOS 27 provisioning flow can create the guest account, enable automatic login, enable SSH, and skip Setup Assistant. This reduces one-time host UI interaction and supports the requirement that later UI test runs remain independent of Jack's host input devices.

macOS 27 is selected for both host and guest because automatic provisioning requires macOS 27 on both sides. Xcode 27 Beta supports macOS Tahoe 26.4 or later, so the selected guest satisfies the toolchain floor.

Official references:

- Apple macOS virtualization sample: https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon
- Apple Xcode system requirements: https://developer.apple.com/xcode/system-requirements/
- VirtualBuddy project and installation model: https://github.com/insidegui/VirtualBuddy
- VirtualBuddy 2.2 release notes: https://github.com/insidegui/VirtualBuddy/releases

## Isolation and Data Protection

The VM library remains in VirtualBuddy's application-support directory. No VM disk image is stored in a CornerPet repository.

The guest receives source through a Git bundle containing the exact branch or commit under test. The guest creates its own clone from that bundle. The host repository is never mounted writable in the guest, so builds, derived data, tests, and accidental Git operations cannot change Jack's host checkout.

An exchange directory outside the repositories may contain only:

- Git bundles prepared for a named verification run.
- Test result bundles and human-readable summaries copied from the guest.
- Non-secret setup metadata such as guest hostname and tool versions.

The guest account uses a generated password stored in the host login keychain. The password must not appear in command output, documentation, Git history, or test evidence. The guest does not sign in to an Apple Account.

## Execution Model

VirtualBuddy keeps the guest booted and automatically logged in. The guest's graphical session remains unlocked while UI tests run.

The host initiates work over SSH. Before a guarded UI suite, the guest verifies:

1. The expected CornerPet commit is checked out and the worktree is clean.
2. The selected developer directory points to the guest Xcode 27 Beta installation.
3. The guest has an active Aqua console session for `cornerpet-test`.
4. The active keyboard input source is ABC and no third-party input method is installed.

The Task 12.5 runner then executes all 21 guarded UI tests inside the guest. The result bundle and runner summary are copied back to the host exchange directory. A passing result is valid only when the runner reports 21 executed tests, zero failures, and no infrastructure classification.

## Host Resource Policy

The host has 18 GB physical memory, 11 logical CPUs, and more than 500 GB currently available. The guest is limited to four virtual CPUs and 8 GiB memory to preserve enough capacity for ordinary host work.

Only one VM runs at a time. The guest may make the host slower during Xcode builds, but guest UI automation must not move the host pointer or redirect host application focus.

## Failure Handling

- If VirtualBuddy cannot provision macOS 27, retain diagnostic logs and stop before trying another hypervisor or changing host security settings.
- If SSH is unavailable, use the guest UI only for diagnosis; do not silently revert to running the CornerPet UI suite on the host.
- If XCUITest cannot run from the remote invocation while an Aqua session is active, install a guest LaunchAgent that executes the existing project runner in the logged-in GUI bootstrap domain. Do not weaken test assertions.
- If the guest drifts from ABC, treat the run as automation infrastructure failure under the Task 12.5 runner contract.
- Do not push, merge, or create the Task 13 implementation branch until the complete Task 12.5 gate passes.

## Acceptance Criteria

- VirtualBuddy and the VM are installed without modifying CornerPet source code or host Git state.
- `CornerPet-UI-Test` boots macOS 27 with the specified CPU, memory, storage, account, automatic-login, SSH, and network configuration.
- The guest reports the intended macOS, Xcode, Swift, Git, and CornerPet commit versions.
- Host-to-guest command execution works without interactive use of the guest desktop.
- A harmless guest UI automation probe completes without moving the host pointer or changing host application focus.
- Task 12.5 executes exactly 21 guarded UI tests in the guest with zero failures and produces retained result evidence.
- Only after that gate passes, the latest Task 12.5 history is integrated into `main`, synchronized with `origin/main`, and the isolated `codex/cornerpet-task-13` boundary is created from that verified baseline.

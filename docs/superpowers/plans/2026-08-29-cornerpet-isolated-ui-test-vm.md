# CornerPet Isolated UI Test VM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an isolated macOS 27 VM that runs CornerPet UI automation without controlling the host desktop, use it to close the Task 12.5 gate, and only then begin Task 13 from verified `origin/main`.

**Architecture:** VirtualBuddy runs one Apple Virtualization-based guest with automatic login and SSH. Source enters the guest as an explicit Git bundle, builds and tests remain guest-local, and only verification evidence returns to a host exchange directory outside all repositories.

**Tech Stack:** Apple Virtualization framework, VirtualBuddy 2.2 Beta 4, macOS 27, Xcode 27 Beta, SSH, Git bundles, Xcode result bundles.

**Spec:** `docs/superpowers/specs/2026-08-29-cornerpet-isolated-ui-test-vm-design.md`

## Global Constraints

- Use four virtual CPUs, 8 GiB memory, a 120 GB boot disk, and NAT networking.
- Do not sign the guest into an Apple Account or expose personal host folders.
- Do not mount any host CornerPet worktree writable in the guest.
- Never print or commit the generated guest password.
- Do not run the guarded UI suite on the host after this plan starts.
- Do not push or merge Task 12.5, or create Task 13, until the guest executes exactly 21 guarded UI tests with zero failures and no infrastructure classification.

---

### Task 1: Install and verify the virtualization manager

**Files:**
- Create outside Git: `/Users/jack/.codex/vm/CornerPet-UI-Test/`
- Modify outside Git: `/Applications/VirtualBuddy.app`

**Interfaces:**
- Consumes: Homebrew cask `virtualbuddy@beta`
- Produces: signed VirtualBuddy 2.2 Beta 4 application and `vctool`

- [ ] **Step 1: Record the clean host and Git baseline**

Run read-only host, disk, branch, worktree, and remote-ref checks. Save only non-secret environment metadata under `/Users/jack/.codex/vm/CornerPet-UI-Test/host-baseline.txt`.

- [ ] **Step 2: Install VirtualBuddy**

Run `brew install --cask virtualbuddy@beta`.

- [ ] **Step 3: Verify the installed artifact**

Check the application version, Team Identifier or ad-hoc signature details, Gatekeeper assessment, quarantine state, and `vctool --help`. Stop if the installed version is not the expected 2.2 beta series or macOS rejects the app.

- [ ] **Step 4: Commit**

No repository commit is required because this task changes only host tooling. Record the verified version in `host-baseline.txt`.

### Task 2: Create and provision the guest

**Files:**
- Create outside Git: VirtualBuddy VM package under its application-support library
- Create outside Git: host login-keychain item `CornerPet-UI-Test`

**Interfaces:**
- Consumes: VirtualBuddy, Apple's macOS 27 restore image catalog
- Produces: bootable VM `CornerPet-UI-Test`, account `cornerpet-test`, automatic login, Remote Login

- [ ] **Step 1: Create the guest credential safely**

Generate a random password directly into the host login keychain under service `CornerPet-UI-Test` and account `cornerpet-test`. Do not emit the password to stdout or any file.

- [ ] **Step 2: Configure the VM**

Use VirtualBuddy's macOS 27 provisioning flow. Name the VM `CornerPet-UI-Test`; allocate four CPUs, 8 GiB RAM, a 120 GB boot disk, NAT networking, automatic login, and Remote Login.

- [ ] **Step 3: Download and install macOS**

Allow VirtualBuddy to fetch the restore image from Apple's catalog and complete installation. Preserve VirtualBuddy installation logs if provisioning fails; do not switch hypervisors or change host security settings.

- [ ] **Step 4: Verify first boot**

Confirm the VM reaches an automatically logged-in macOS 27 desktop and identify its private address or Bonjour hostname without adding an Apple Account.

- [ ] **Step 5: Verify host isolation**

Move VirtualBuddy out of focus and confirm the guest remains available over SSH. Record guest macOS and hardware values in `guest-baseline.txt`.

### Task 3: Install the guest development toolchain

**Files:**
- Copy into guest: `/Applications/Xcode-beta.app`
- Create in guest: `~/CornerPet/`

**Interfaces:**
- Consumes: host Xcode 27 Beta, SSH access, Task 12.5 Git bundle
- Produces: initialized Xcode toolchain and isolated CornerPet clone at the exact recorded Task 12.5 branch head

- [ ] **Step 1: Transfer Xcode**

Copy the host Xcode application to the guest over the private VM network, preserving extended attributes and application-bundle structure.

- [ ] **Step 2: Initialize Xcode**

Select the verified guest Xcode developer directory, accept its license, and run first-launch component installation in the guest. Verify `xcodebuild -version` and `swift --version` match the required Xcode 27 and Swift 6.4 toolchain family. Because this is a dedicated unattended UI-test machine, use the system-provided `automationmodetool enable-automationmode-without-authentication` command once with administrator authorization, then reboot and verify its status; do not weaken Gatekeeper or host security settings.

- [ ] **Step 3: Prepare the exact source bundle**

Resolve and record `codex/cornerpet-task-12-5` with `git rev-parse`, create `/Users/jack/.codex/vm/CornerPet-UI-Test/exchange/task-12-5.bundle` from that exact object, verify the bundle, and transfer it to the guest.

- [ ] **Step 4: Clone and verify source isolation**

Clone the bundle to `~/CornerPet`, check out `codex/cornerpet-task-12-5`, verify `HEAD` equals the object recorded before bundle creation, and confirm a clean guest worktree with no writable host worktree mount.

- [ ] **Step 5: Run non-UI smoke checks**

Run the project runner contract tests and a unit-test smoke command inside the guest. Preserve their logs under the host exchange directory.

### Task 4: Prove background UI automation and close Task 12.5

**Files:**
- Create in guest: result bundles under `~/CornerPet/build/test-evidence/`
- Copy to host: `/Users/jack/.codex/vm/CornerPet-UI-Test/exchange/task-12-5-evidence/`

**Interfaces:**
- Consumes: active guest Aqua session, ABC input source, guest Task 12.5 clone
- Produces: isolated UI probe evidence and complete guarded UI-suite evidence

- [ ] **Step 1: Verify guest GUI preconditions**

Confirm `cornerpet-test` owns the active console session, ABC is selected, no third-party input source is installed, and the guest screen is unlocked.

- [ ] **Step 2: Run a harmless UI automation probe**

From the host, run `CORNERPET_AD_HOC_SIGNING=1 Scripts/run-ui-tests.sh --probe-only` over SSH while VirtualBuddy is not the host's focused app. This executable mode uses the normal input-source guard, signs test products locally without a development team, and selects only `CornerPetLaunchTests.testApplicationLaunchesWithoutMainWindow`. Confirm the result succeeds without bringing VirtualBuddy forward or changing the host pointer position; retain the command output as probe evidence.

- [ ] **Step 3: Run the complete guarded suite**

Execute `CORNERPET_AD_HOC_SIGNING=1 Scripts/run-ui-tests.sh` inside the guest. Require exactly 21 executed tests, zero failures, exit status zero, and no infrastructure classification.

- [ ] **Step 4: Export and inspect evidence**

Copy the `.xcresult`, summary, test count, failure count, tool versions, and tested commit back to the host exchange directory. Inspect the result bundle rather than relying only on process exit status.

- [ ] **Step 5: Commit**

If verification documentation changes, update `docs/verification/task-12-5-verification.md`, run `git diff --check`, and commit only the evidence metadata with `docs: verify Task 12.5 in isolated VM`. Do not commit binary result bundles.

### Task 5: Integrate Task 12.5 and establish Task 13

**Files:**
- Modify Git refs only after Task 12.5 passes
- Create guest clone/worktree for `codex/cornerpet-task-13`

**Interfaces:**
- Consumes: verified Task 12.5 commit and 21-test guest evidence
- Produces: synchronized `origin/main` and isolated Task 13 development boundary

- [ ] **Step 1: Recheck all Git boundaries**

Fetch origin, confirm no unexpected remote movement, inspect host worktrees for user changes, and verify the exact Task 12.5 commits intended for integration.

- [ ] **Step 2: Integrate without rewriting history**

Bring the verified Task 12.5 commits into local `main` with a normal merge or additional merge as required by the current graph. Run the project-required unit and Release gates against the resulting tree.

- [ ] **Step 3: Synchronize the verified baseline**

Push the Task 12.5 branch and `main` without force only when the local and remote graphs are safe and all gates remain green. Verify `origin/main` resolves to the tested tree.

- [ ] **Step 4: Create Task 13 from verified `origin/main`**

Create `codex/cornerpet-task-13` from the updated `origin/main` in the isolated VM. Do not reuse the Task 12.5 worktree for implementation.

- [ ] **Step 5: Begin Task 13 with its required workflow**

Read the Task 13 requirements and applicable project files inside the guest, confirm design against the approved scope, write failing localization and accessibility tests first, and deliver Task 13 as small verified commits.

## Plan Self-Review

- Every VM-design acceptance criterion maps to Tasks 1 through 4.
- The Task 12.5-to-Task 13 ordering constraint maps to Task 5.
- Secrets and binary evidence stay outside Git.
- No step permits force push, branch deletion, host worktree mounting, or host UI-suite execution.
- No product-code implementation begins before the verified Task 12.5 gate.

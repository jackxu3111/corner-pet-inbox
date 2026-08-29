# CornerPet macOS Release Runbook

## Release baseline

CornerPet's first engineering release baseline is:

```text
Marketing version: 0.1.0
Build number:      1
Bundle identifier: com.jack.CornerPet
Architecture:      arm64
Deployment target: macOS 14.0
Distribution:      Developer ID outside the Mac App Store
```

The app target's Release configuration uses manual `Developer ID Application` signing and enables Hardened Runtime without exceptions. Debug remains on Apple Development signing. The generated Info.plist receives `CFBundleShortVersionString`, `CFBundleVersion`, and `LSUIElement=YES` from build settings.

Apple requires Developer ID signing, Hardened Runtime, a secure timestamp, and notarization for current outside-the-store distribution:

- [Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Configuring the Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)

## What is locally verifiable now

Run an unsigned Release build without Apple distribution credentials:

```bash
Scripts/release.sh local-build
```

The artifact is written to:

```text
build/release/unsigned/CornerPet.app
```

This proves the Release configuration compiles for arm64. It is not a distributable artifact and must not be presented as signed, notarized, or Gatekeeper-approved.

Run the isolated workflow contract tests:

```bash
/bin/bash Scripts/Tests/release-tests.sh
```

These tests use fake commands and a temporary Applications directory. They never contact Apple and never write to the real `/Applications`.

## External prerequisites

Before producing a distributable build, the release operator needs:

1. Apple Developer Program access for team `BA2HVLXM26`.
2. A valid private key and `Developer ID Application` certificate installed in the login keychain.
3. Notarization credentials stored in the keychain under a dedicated profile name.

Create or download the certificate through the Apple Developer account and Keychain Access. Confirm it without exposing private material:

```bash
security find-identity -v -p codesigning
```

Create the notarytool profile interactively. The profile name in this runbook is an example, not a secret:

```bash
xcrun notarytool store-credentials "CornerPet-Notary"
```

Follow the prompts for Apple ID or App Store Connect API credentials. Do not put passwords, private keys, issuer secrets, or app-specific passwords in this repository, shell scripts, screenshots, or task logs.

Export only the profile name and the exact installed certificate label for the release process:

```bash
export CORNERPET_NOTARY_PROFILE="CornerPet-Notary"
export CORNERPET_DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
```

## Credentialed release procedure

### 1. Preflight

```bash
Scripts/release.sh preflight
```

Preflight requires the exact Developer ID Application identity and validates the named keychain profile with `notarytool history`. It stops before archiving if either prerequisite is unavailable.

### 2. Archive and verify the signature

```bash
Scripts/release.sh archive
```

The command creates:

```text
build/release/CornerPet-0.1.0-1.xcarchive
```

It uses the Release configuration, manual Developer ID identity, team ID, and Hardened Runtime, then runs strict deep signature verification and prints the signature details. Inspect those details for the Developer ID authority, secure timestamp, and runtime flag before continuing.

### 3. Notarize, staple, and assess

```bash
Scripts/release.sh notarize
```

The command:

1. verifies the signed app;
2. creates `CornerPet-0.1.0-1-submission.zip` with `ditto`;
3. submits it through `notarytool --wait` using the keychain profile;
4. saves `notary-response.json`;
5. obtains `notary-log.json` when an ID is available after failure;
6. staples and validates the accepted ticket;
7. repeats strict signature verification and runs Gatekeeper assessment;
8. creates `CornerPet-0.1.0-1-notarized.zip` from the stapled app.

Only the `-notarized.zip` artifact is a distribution candidate.

### 4. Install safely

The default install command refuses to overwrite an existing app:

```bash
Scripts/release.sh install
```

If `/Applications/CornerPet.app` already exists and replacement is intended:

```bash
Scripts/release.sh install --replace
```

The old app is moved to a timestamped, recoverable backup under `build/release/backups/` before the new app is copied. If copying fails, the script restores the backup when possible.

### 5. Verify the installed app

```bash
Scripts/release.sh verify-installed
```

This checks the installed version, build, bundle identifier, LSUIElement value, stapled ticket, and Gatekeeper assessment, launches the app, and confirms the process remains running. Because CornerPet is an accessory app, a normal result has no Dock icon.

## Login-launch acceptance

Login startup is intentionally not changed by the release script. Complete this user-authorized session check after installing the notarized app:

1. Launch `/Applications/CornerPet.app`.
2. Open CornerPet Settings and enable Launch at Login.
3. Confirm macOS System Settings shows CornerPet under Login Items.
4. Quit CornerPet.
5. Log out and back in, or restart the Mac.
6. Confirm CornerPet runs without a Dock icon or visible panel at startup.
7. Trigger a configured corner and confirm capture works.
8. Confirm draft, archive/favorite content, settings, pin size, and reminder state are preserved.

Record the OS build, app version/build, result, and any prompt shown by macOS. Do not report this check as passed until a real logout or restart has occurred.

## Failure recovery

- **No Developer ID identity:** install the valid certificate and private key; do not substitute Apple Development or ad-hoc signing.
- **Notary profile rejected:** recreate the keychain profile outside the repository and rerun `preflight`.
- **Notarization rejected:** inspect `notary-response.json` and `notary-log.json`; fix the reported signing or bundle issue, create a new build number, and rebuild. Do not resubmit a modified bundle under the same release evidence.
- **Gatekeeper rejection after acceptance:** retain the archive, response, log, and signature details; do not bypass Gatekeeper for a distribution acceptance claim.
- **Install copy failure:** use the path printed as `CORNERPET_RELEASE_INSTALL_BACKUP` or the newest app under `build/release/backups/`.
- **Login launch fails:** inspect the app's Launch at Login setting and macOS Login Items UI. Do not modify ServiceManagement databases directly.

Release artifacts under `build/` are intentionally ignored by Git. Certificates, private keys, notary credentials, and signed binaries are never committed.

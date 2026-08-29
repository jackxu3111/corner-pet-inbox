#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RELEASE_SCRIPT="$PROJECT_ROOT/Scripts/release.sh"
PASS_COUNT=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        fail "did not expect '$unexpected' in $file"
    fi
}

assert_equals() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

make_fixture() {
    FIXTURE_DIR="$(mktemp -d)"
    ARTIFACTS_DIR="$FIXTURE_DIR/artifacts"
    APPLICATIONS_DIR="$FIXTURE_DIR/Applications"
    COMMAND_LOG="$FIXTURE_DIR/commands.log"
    RUN_OUTPUT="$FIXTURE_DIR/run-output"
    mkdir -p "$ARTIFACTS_DIR" "$APPLICATIONS_DIR" "$FIXTURE_DIR/Developer" "$FIXTURE_DIR/bin"
    : > "$COMMAND_LOG"

cat > "$FIXTURE_DIR/bin/xcodebuild" <<'FAKE_XCODEBUILD'
#!/bin/bash
set -u
echo "xcodebuild $*" >> "$FAKE_COMMAND_LOG"
if [[ "${FAKE_XCODEBUILD_REQUIRE_MISSING_OUTPUT:-0}" == "1" ]]; then
    for argument in "$@"; do
        if [[ "$argument" == CONFIGURATION_BUILD_DIR=* ]]; then
            output_directory="${argument#CONFIGURATION_BUILD_DIR=}"
            [[ ! -e "$output_directory" ]] || exit 88
        fi
    done
fi
exit "${FAKE_XCODEBUILD_EXIT:-0}"
FAKE_XCODEBUILD

    cat > "$FIXTURE_DIR/bin/security" <<'FAKE_SECURITY'
#!/bin/bash
set -u
echo "security $*" >> "$FAKE_COMMAND_LOG"
printf '%s\n' "${FAKE_SECURITY_IDENTITIES:-}"
exit "${FAKE_SECURITY_EXIT:-0}"
FAKE_SECURITY

    cat > "$FIXTURE_DIR/bin/xcrun" <<'FAKE_XCRUN'
#!/bin/bash
set -u
echo "xcrun $*" >> "$FAKE_COMMAND_LOG"
if [[ "${1:-}" == "notarytool" && "${2:-}" == "history" ]]; then
    exit "${FAKE_NOTARY_HISTORY_EXIT:-0}"
fi
exit 0
FAKE_XCRUN

    cat > "$FIXTURE_DIR/bin/codesign" <<'FAKE_CODESIGN'
#!/bin/bash
set -u
echo "codesign $*" >> "$FAKE_COMMAND_LOG"
exit 0
FAKE_CODESIGN

    cat > "$FIXTURE_DIR/bin/spctl" <<'FAKE_SPCTL'
#!/bin/bash
set -u
echo "spctl $*" >> "$FAKE_COMMAND_LOG"
exit 0
FAKE_SPCTL

    cat > "$FIXTURE_DIR/bin/open" <<'FAKE_OPEN'
#!/bin/bash
set -u
echo "open $*" >> "$FAKE_COMMAND_LOG"
exit 0
FAKE_OPEN

    cat > "$FIXTURE_DIR/bin/pgrep" <<'FAKE_PGREP'
#!/bin/bash
echo "pgrep $*" >> "$FAKE_COMMAND_LOG"
exit 0
FAKE_PGREP

    chmod +x "$FIXTURE_DIR/bin/"*
}

cleanup_fixture() {
    rm -rf "$FIXTURE_DIR"
}

run_release() {
    set +e
    FAKE_COMMAND_LOG="$COMMAND_LOG" \
    FAKE_XCODEBUILD_EXIT="${FAKE_XCODEBUILD_EXIT:-0}" \
    FAKE_XCODEBUILD_REQUIRE_MISSING_OUTPUT="${FAKE_XCODEBUILD_REQUIRE_MISSING_OUTPUT:-0}" \
    FAKE_SECURITY_IDENTITIES="${FAKE_SECURITY_IDENTITIES:-}" \
    FAKE_SECURITY_EXIT="${FAKE_SECURITY_EXIT:-0}" \
    FAKE_NOTARY_HISTORY_EXIT="${FAKE_NOTARY_HISTORY_EXIT:-0}" \
    CORNERPET_DEVELOPER_DIR="$FIXTURE_DIR/Developer" \
    CORNERPET_XCODEBUILD="$FIXTURE_DIR/bin/xcodebuild" \
    CORNERPET_SECURITY="$FIXTURE_DIR/bin/security" \
    CORNERPET_XCRUN="$FIXTURE_DIR/bin/xcrun" \
    CORNERPET_CODESIGN="$FIXTURE_DIR/bin/codesign" \
    CORNERPET_SPCTL="$FIXTURE_DIR/bin/spctl" \
    CORNERPET_DITTO="/usr/bin/ditto" \
    CORNERPET_OPEN="$FIXTURE_DIR/bin/open" \
    CORNERPET_PGREP="$FIXTURE_DIR/bin/pgrep" \
    CORNERPET_ARTIFACTS_DIR="$ARTIFACTS_DIR" \
    CORNERPET_APPLICATIONS_DIR="$APPLICATIONS_DIR" \
    CORNERPET_DEVELOPER_ID_APPLICATION="${CORNERPET_DEVELOPER_ID_APPLICATION:-}" \
    CORNERPET_NOTARY_PROFILE="${CORNERPET_NOTARY_PROFILE:-}" \
    /bin/bash "$RELEASE_SCRIPT" "$@" > "$RUN_OUTPUT" 2>&1
    RUN_STATUS=$?
    set -e
}

make_fake_archived_app() {
    ARCHIVED_APP="$ARTIFACTS_DIR/CornerPet-0.1.0-1.xcarchive/Products/Applications/CornerPet.app"
    mkdir -p "$ARCHIVED_APP/Contents"
    printf '%s\n' "new app" > "$ARCHIVED_APP/Contents/new-marker"
}

make_fake_installed_app() {
    local installed_contents="$APPLICATIONS_DIR/CornerPet.app/Contents"
    mkdir -p "$installed_contents/MacOS"
    cat > "$installed_contents/Info.plist" <<'FAKE_INFO_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.jack.CornerPet</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
FAKE_INFO_PLIST
    : > "$installed_contents/MacOS/CornerPet"
    chmod +x "$installed_contents/MacOS/CornerPet"
}

test_local_build_is_unsigned_release_arm64() {
    make_fixture

    run_release local-build

    assert_equals "$RUN_STATUS" "0" "local-build status"
    assert_contains "$COMMAND_LOG" "xcodebuild clean build"
    assert_contains "$COMMAND_LOG" "-configuration Release"
    assert_contains "$COMMAND_LOG" "platform=macOS,arch=arm64"
    assert_contains "$COMMAND_LOG" "CODE_SIGNING_ALLOWED=NO"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_local_build_propagates_xcode_failure() {
    make_fixture
    FAKE_XCODEBUILD_EXIT=65

    run_release local-build

    assert_equals "$RUN_STATUS" "65" "failed local-build status"
    assert_not_contains "$RUN_OUTPUT" "CORNERPET_RELEASE_UNSIGNED_APP="
    cleanup_fixture
    unset FAKE_XCODEBUILD_EXIT
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_local_build_leaves_output_directory_to_xcode() {
    make_fixture
    FAKE_XCODEBUILD_REQUIRE_MISSING_OUTPUT=1

    run_release local-build

    assert_equals "$RUN_STATUS" "0" "build-system-owned output status"
    cleanup_fixture
    unset FAKE_XCODEBUILD_REQUIRE_MISSING_OUTPUT
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_preflight_rejects_missing_developer_id_identity() {
    make_fixture
    FAKE_SECURITY_IDENTITIES='1) ABC "Apple Development: Example (TEAM)"'
    CORNERPET_NOTARY_PROFILE="CornerPet-Notary"

    run_release preflight

    [[ "$RUN_STATUS" -ne 0 ]] || fail "preflight accepted a missing Developer ID identity"
    assert_contains "$RUN_OUTPUT" "Developer ID Application"
    assert_not_contains "$COMMAND_LOG" "notarytool history"
    cleanup_fixture
    unset FAKE_SECURITY_IDENTITIES CORNERPET_NOTARY_PROFILE
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_preflight_rejects_missing_notary_profile() {
    make_fixture
    FAKE_SECURITY_IDENTITIES='1) ABC "Developer ID Application: Example (TEAM)"'
    CORNERPET_DEVELOPER_ID_APPLICATION="Developer ID Application: Example (TEAM)"

    run_release preflight

    [[ "$RUN_STATUS" -ne 0 ]] || fail "preflight accepted a missing notary profile"
    assert_contains "$RUN_OUTPUT" "CORNERPET_NOTARY_PROFILE"
    assert_not_contains "$COMMAND_LOG" "notarytool history"
    cleanup_fixture
    unset FAKE_SECURITY_IDENTITIES CORNERPET_DEVELOPER_ID_APPLICATION
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_install_refuses_existing_app_without_replace() {
    make_fixture
    make_fake_archived_app
    mkdir -p "$APPLICATIONS_DIR/CornerPet.app/Contents"
    printf '%s\n' "old app" > "$APPLICATIONS_DIR/CornerPet.app/Contents/old-marker"

    run_release install

    [[ "$RUN_STATUS" -ne 0 ]] || fail "install overwrote an existing app without --replace"
    [[ -f "$APPLICATIONS_DIR/CornerPet.app/Contents/old-marker" ]] || fail "existing app was changed"
    assert_contains "$RUN_OUTPUT" "--replace"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_install_replace_keeps_recoverable_backup() {
    make_fixture
    make_fake_archived_app
    mkdir -p "$APPLICATIONS_DIR/CornerPet.app/Contents"
    printf '%s\n' "old app" > "$APPLICATIONS_DIR/CornerPet.app/Contents/old-marker"

    run_release install --replace

    assert_equals "$RUN_STATUS" "0" "replace install status"
    [[ -f "$APPLICATIONS_DIR/CornerPet.app/Contents/new-marker" ]] || fail "new app was not installed"
    backup_marker="$(find "$ARTIFACTS_DIR/backups" -name old-marker -type f -print -quit)"
    [[ -n "$backup_marker" ]] || fail "existing app was not backed up"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_verify_installed_matches_the_installed_executable() {
    make_fixture
    make_fake_installed_app

    run_release verify-installed

    assert_equals "$RUN_STATUS" "0" "installed-app verification status"
    assert_contains "$COMMAND_LOG" "pgrep -f -x $APPLICATIONS_DIR/CornerPet.app/Contents/MacOS/CornerPet"
    assert_not_contains "$COMMAND_LOG" "pgrep -x CornerPet"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_unsafe_artifact_path_and_unknown_command_are_rejected() {
    make_fixture
    ARTIFACTS_DIR="/"

    run_release local-build
    [[ "$RUN_STATUS" -ne 0 ]] || fail "root artifact path was accepted"
    assert_not_contains "$COMMAND_LOG" "xcodebuild"

    ARTIFACTS_DIR="$FIXTURE_DIR/artifacts"
    run_release something-else
    [[ "$RUN_STATUS" -ne 0 ]] || fail "unknown command was accepted"
    assert_contains "$RUN_OUTPUT" "usage:"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_unsafe_applications_path_is_rejected_before_install() {
    make_fixture
    make_fake_archived_app
    APPLICATIONS_DIR="relative-applications"

    run_release install

    [[ "$RUN_STATUS" -ne 0 ]] || fail "relative applications path was accepted"
    assert_contains "$RUN_OUTPUT" "applications directory must be absolute"
    assert_not_contains "$COMMAND_LOG" "stapler validate"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_effective_release_build_settings() {
    local settings
    settings="$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
        -project "$PROJECT_ROOT/CornerPet.xcodeproj" \
        -scheme CornerPet \
        -configuration Release \
        -showBuildSettings 2>/dev/null)"

    grep -Eq '^[[:space:]]*MARKETING_VERSION = 0\.1\.0$' <<< "$settings" || fail "MARKETING_VERSION is not 0.1.0"
    grep -Eq '^[[:space:]]*CURRENT_PROJECT_VERSION = 1$' <<< "$settings" || fail "CURRENT_PROJECT_VERSION is not 1"
    grep -Eq '^[[:space:]]*ENABLE_HARDENED_RUNTIME = YES$' <<< "$settings" || fail "Hardened Runtime is not enabled"
    grep -Eq '^[[:space:]]*ENABLE_TESTABILITY = NO$' <<< "$settings" || fail "Release testability is not disabled"
    grep -Eq '^[[:space:]]*CODE_SIGN_IDENTITY = Developer ID Application$' <<< "$settings" || fail "Release does not use Developer ID Application"
    PASS_COUNT=$((PASS_COUNT + 1))
}

set -e
[[ -f "$RELEASE_SCRIPT" ]] || fail "missing release script: $RELEASE_SCRIPT"

test_local_build_is_unsigned_release_arm64
test_local_build_propagates_xcode_failure
test_local_build_leaves_output_directory_to_xcode
test_preflight_rejects_missing_developer_id_identity
test_preflight_rejects_missing_notary_profile
test_install_refuses_existing_app_without_replace
test_install_replace_keeps_recoverable_backup
test_verify_installed_matches_the_installed_executable
test_unsafe_artifact_path_and_unknown_command_are_rejected
test_unsafe_applications_path_is_rejected_before_install
test_effective_release_build_settings

echo "PASS: $PASS_COUNT release workflow tests"

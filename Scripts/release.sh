#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
VERSION="0.1.0"
BUILD_NUMBER="1"
BUNDLE_IDENTIFIER="com.jack.CornerPet"
TEAM_ID="BA2HVLXM26"
APP_NAME="CornerPet.app"

usage() {
    cat <<'USAGE'
usage: Scripts/release.sh <command> [options]

commands:
  local-build              Build an unsigned arm64 Release app locally.
  preflight                Validate Developer ID and notary keychain prerequisites.
  archive                  Create and verify a Developer ID-signed archive.
  notarize                 Package, notarize, staple, and verify the archived app.
  install [--replace]      Install the verified app; keep a backup when replacing.
  verify-installed         Inspect and launch /Applications/CornerPet.app.
USAGE
}

fail() {
    echo "error: $*" >&2
    exit 1
}

resolve_developer_dir() {
    if [[ -n "${CORNERPET_DEVELOPER_DIR:-}" ]]; then
        printf '%s\n' "$CORNERPET_DEVELOPER_DIR"
    elif [[ -n "${DEVELOPER_DIR:-}" ]]; then
        printf '%s\n' "$DEVELOPER_DIR"
    elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
    elif [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
        printf '%s\n' "/Applications/Xcode-beta.app/Contents/Developer"
    else
        return 1
    fi
}

require_executable() {
    [[ -x "$1" ]] || fail "required command is not executable: $1"
}

validate_artifacts_directory() {
    [[ -n "$ARTIFACTS_DIR" ]] || fail "artifact directory is empty"
    [[ "$ARTIFACTS_DIR" == /* ]] || fail "artifact directory must be absolute: $ARTIFACTS_DIR"
    [[ "$ARTIFACTS_DIR" != "/" ]] || fail "refusing to use / as the artifact directory"
    [[ "$ARTIFACTS_DIR" != "$PROJECT_ROOT" ]] || fail "refusing to use the project root as the artifact directory"
}

validate_applications_directory() {
    [[ -n "$APPLICATIONS_DIR" ]] || fail "applications directory is empty"
    [[ "$APPLICATIONS_DIR" == /* ]] || fail "applications directory must be absolute: $APPLICATIONS_DIR"
    [[ "$APPLICATIONS_DIR" != "/" ]] || fail "refusing to use / as the applications directory"
    [[ "$APPLICATIONS_DIR" != "$PROJECT_ROOT" ]] || fail "refusing to use the project root as the applications directory"
}

ensure_absent() {
    [[ ! -e "$1" ]] || fail "artifact already exists: $1"
}

DEVELOPER_DIR_RESOLVED="$(resolve_developer_dir)" || fail "no full Xcode developer directory found"
XCODEBUILD="${CORNERPET_XCODEBUILD:-$DEVELOPER_DIR_RESOLVED/usr/bin/xcodebuild}"
SECURITY="${CORNERPET_SECURITY:-/usr/bin/security}"
XCRUN="${CORNERPET_XCRUN:-/usr/bin/xcrun}"
CODESIGN="${CORNERPET_CODESIGN:-/usr/bin/codesign}"
SPCTL="${CORNERPET_SPCTL:-/usr/sbin/spctl}"
DITTO="${CORNERPET_DITTO:-/usr/bin/ditto}"
OPEN="${CORNERPET_OPEN:-/usr/bin/open}"
PGREP="${CORNERPET_PGREP:-/usr/bin/pgrep}"
PLUTIL="${CORNERPET_PLUTIL:-/usr/bin/plutil}"
ARTIFACTS_DIR="${CORNERPET_ARTIFACTS_DIR:-$PROJECT_ROOT/build/release}"
APPLICATIONS_DIR="${CORNERPET_APPLICATIONS_DIR:-/Applications}"
ARCHIVE_PATH="$ARTIFACTS_DIR/CornerPet-$VERSION-$BUILD_NUMBER.xcarchive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
SUBMISSION_ZIP="$ARTIFACTS_DIR/CornerPet-$VERSION-$BUILD_NUMBER-submission.zip"
NOTARIZED_ZIP="$ARTIFACTS_DIR/CornerPet-$VERSION-$BUILD_NUMBER-notarized.zip"
NOTARY_RESPONSE="$ARTIFACTS_DIR/notary-response.json"

validate_artifacts_directory
validate_applications_directory
mkdir -p "$ARTIFACTS_DIR"

find_developer_id_identity() {
    require_executable "$SECURITY"
    local identities requested identity
    identities="$($SECURITY find-identity -v -p codesigning 2>&1)" || fail "unable to query code-signing identities"
    requested="${CORNERPET_DEVELOPER_ID_APPLICATION:-}"

    if [[ -n "$requested" ]]; then
        [[ "$requested" == Developer\ ID\ Application:* ]] || fail "requested identity is not a Developer ID Application identity"
        grep -Fq -- "\"$requested\"" <<< "$identities" || fail "Developer ID Application identity is unavailable: $requested"
        identity="$requested"
    else
        identity="$(sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' <<< "$identities" | head -n 1)"
        [[ -n "$identity" ]] || fail "no Developer ID Application identity is installed"
    fi

    printf '%s\n' "$identity"
}

run_preflight() {
    require_executable "$XCRUN"
    DEVELOPER_ID_IDENTITY="$(find_developer_id_identity)" || exit 1
    NOTARY_PROFILE="${CORNERPET_NOTARY_PROFILE:-}"
    [[ -n "$NOTARY_PROFILE" ]] || fail "CORNERPET_NOTARY_PROFILE must name a notarytool keychain profile"

    if ! DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" notarytool history \
        --keychain-profile "$NOTARY_PROFILE" \
        --output-format json > "$ARTIFACTS_DIR/notary-history.json"; then
        fail "notarytool could not use keychain profile: $NOTARY_PROFILE"
    fi

    echo "CORNERPET_RELEASE_DEVELOPER_ID=$DEVELOPER_ID_IDENTITY"
    echo "CORNERPET_RELEASE_NOTARY_PROFILE=$NOTARY_PROFILE"
}

local_build() {
    require_executable "$XCODEBUILD"
    local output_dir="$ARTIFACTS_DIR/unsigned"

    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCODEBUILD" clean build \
        -project "$PROJECT_ROOT/CornerPet.xcodeproj" \
        -scheme CornerPet \
        -configuration Release \
        -destination "platform=macOS,arch=arm64" \
        CONFIGURATION_BUILD_DIR="$output_dir" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO

    echo "CORNERPET_RELEASE_UNSIGNED_APP=$output_dir/$APP_NAME"
}

archive_app() {
    require_executable "$XCODEBUILD"
    require_executable "$CODESIGN"
    run_preflight
    ensure_absent "$ARCHIVE_PATH"

    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCODEBUILD" archive \
        -project "$PROJECT_ROOT/CornerPet.xcodeproj" \
        -scheme CornerPet \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        ENABLE_HARDENED_RUNTIME=YES

    [[ -d "$ARCHIVED_APP" ]] || fail "archive did not contain $ARCHIVED_APP"
    "$CODESIGN" --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
    "$CODESIGN" --display --verbose=4 "$ARCHIVED_APP"
    echo "CORNERPET_RELEASE_ARCHIVE=$ARCHIVE_PATH"
}

write_notary_log_if_available() {
    local submission_id="$1"
    [[ -n "$submission_id" ]] || return 0
    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" notarytool log \
        "$submission_id" \
        --keychain-profile "$NOTARY_PROFILE" \
        "$ARTIFACTS_DIR/notary-log.json" || true
}

notarize_app() {
    require_executable "$CODESIGN"
    require_executable "$DITTO"
    require_executable "$PLUTIL"
    require_executable "$SPCTL"
    run_preflight
    [[ -d "$ARCHIVED_APP" ]] || fail "signed archive is missing: $ARCHIVED_APP"
    ensure_absent "$SUBMISSION_ZIP"
    ensure_absent "$NOTARIZED_ZIP"
    ensure_absent "$NOTARY_RESPONSE"

    "$CODESIGN" --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
    "$DITTO" -c -k --sequesterRsrc --keepParent "$ARCHIVED_APP" "$SUBMISSION_ZIP"

    set +e
    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" notarytool submit \
        "$SUBMISSION_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format json > "$NOTARY_RESPONSE"
    local submit_status=$?
    set -e

    local submission_id notary_status
    submission_id="$($PLUTIL -extract id raw -o - "$NOTARY_RESPONSE" 2>/dev/null || true)"
    notary_status="$($PLUTIL -extract status raw -o - "$NOTARY_RESPONSE" 2>/dev/null || true)"

    if [[ "$submit_status" -ne 0 || "$notary_status" != "Accepted" ]]; then
        write_notary_log_if_available "$submission_id"
        fail "notarization was not accepted; inspect $NOTARY_RESPONSE and the notary log"
    fi

    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" stapler staple "$ARCHIVED_APP"
    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" stapler validate "$ARCHIVED_APP"
    "$CODESIGN" --verify --deep --strict --verbose=2 "$ARCHIVED_APP"
    "$SPCTL" --assess --type execute --verbose=2 "$ARCHIVED_APP"
    "$DITTO" -c -k --sequesterRsrc --keepParent "$ARCHIVED_APP" "$NOTARIZED_ZIP"

    echo "CORNERPET_RELEASE_NOTARIZED_ZIP=$NOTARIZED_ZIP"
}

install_app() {
    local replace_existing=0
    if [[ "${1:-}" == "--replace" ]]; then
        replace_existing=1
        shift
    fi
    [[ $# -eq 0 ]] || fail "usage: Scripts/release.sh install [--replace]"

    require_executable "$XCRUN"
    require_executable "$SPCTL"
    require_executable "$DITTO"
    [[ -d "$ARCHIVED_APP" ]] || fail "notarized archive app is missing: $ARCHIVED_APP"
    [[ -d "$APPLICATIONS_DIR" ]] || fail "applications directory is missing: $APPLICATIONS_DIR"

    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" stapler validate "$ARCHIVED_APP"
    "$SPCTL" --assess --type execute --verbose=2 "$ARCHIVED_APP"

    local destination="$APPLICATIONS_DIR/$APP_NAME"
    local backup_path=""
    if [[ -e "$destination" ]]; then
        [[ "$replace_existing" -eq 1 ]] || fail "$destination already exists; rerun with --replace to keep a recoverable backup"
        local backup_dir="$ARTIFACTS_DIR/backups"
        mkdir -p "$backup_dir"
        backup_path="$backup_dir/CornerPet-before-$VERSION-$BUILD_NUMBER-$(date '+%Y%m%d-%H%M%S').app"
        ensure_absent "$backup_path"
        mv "$destination" "$backup_path"
    fi

    if ! "$DITTO" "$ARCHIVED_APP" "$destination"; then
        if [[ -e "$destination" ]]; then
            mv "$destination" "$ARTIFACTS_DIR/failed-install-$(date '+%Y%m%d-%H%M%S').app"
        fi
        if [[ -n "$backup_path" && -e "$backup_path" ]]; then
            mv "$backup_path" "$destination"
        fi
        fail "installation failed; the previous installation was restored when available"
    fi

    echo "CORNERPET_RELEASE_INSTALLED_APP=$destination"
    if [[ -n "$backup_path" ]]; then
        echo "CORNERPET_RELEASE_INSTALL_BACKUP=$backup_path"
    fi
}

verify_installed_app() {
    require_executable "$XCRUN"
    require_executable "$SPCTL"
    require_executable "$PLUTIL"
    require_executable "$OPEN"
    require_executable "$PGREP"

    local installed_app="$APPLICATIONS_DIR/$APP_NAME"
    local info_plist="$installed_app/Contents/Info.plist"
    local installed_executable="$installed_app/Contents/MacOS/CornerPet"
    [[ -f "$info_plist" ]] || fail "installed Info.plist is missing: $info_plist"
    [[ -x "$installed_executable" ]] || fail "installed executable is missing: $installed_executable"

    local installed_version installed_build lsui_element installed_bundle_id
    installed_version="$($PLUTIL -extract CFBundleShortVersionString raw -o - "$info_plist")"
    installed_build="$($PLUTIL -extract CFBundleVersion raw -o - "$info_plist")"
    lsui_element="$($PLUTIL -extract LSUIElement raw -o - "$info_plist")"
    installed_bundle_id="$($PLUTIL -extract CFBundleIdentifier raw -o - "$info_plist")"
    [[ "$installed_version" == "$VERSION" ]] || fail "installed version is $installed_version, expected $VERSION"
    [[ "$installed_build" == "$BUILD_NUMBER" ]] || fail "installed build is $installed_build, expected $BUILD_NUMBER"
    [[ "$lsui_element" == "true" || "$lsui_element" == "YES" || "$lsui_element" == "1" ]] || fail "installed app is not LSUIElement"
    [[ "$installed_bundle_id" == "$BUNDLE_IDENTIFIER" ]] || fail "installed bundle ID is $installed_bundle_id"

    DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCRUN" stapler validate "$installed_app"
    "$SPCTL" --assess --type execute --verbose=2 "$installed_app"
    "$OPEN" "$installed_app"

    local attempt
    for attempt in {1..20}; do
        if "$PGREP" -f -x "$installed_executable" >/dev/null 2>&1; then
            echo "CORNERPET_RELEASE_INSTALLED_PROCESS=running"
            echo "CORNERPET_RELEASE_LOGIN_RESTART_CHECK=manual-required"
            return 0
        fi
        /bin/sleep 0.25
    done
    fail "CornerPet did not remain running after launch"
}

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    local-build)
        [[ $# -eq 0 ]] || fail "usage: Scripts/release.sh local-build"
        local_build
        ;;
    preflight)
        [[ $# -eq 0 ]] || fail "usage: Scripts/release.sh preflight"
        run_preflight
        ;;
    archive)
        [[ $# -eq 0 ]] || fail "usage: Scripts/release.sh archive"
        archive_app
        ;;
    notarize)
        [[ $# -eq 0 ]] || fail "usage: Scripts/release.sh notarize"
        notarize_app
        ;;
    install)
        install_app "$@"
        ;;
    verify-installed)
        [[ $# -eq 0 ]] || fail "usage: Scripts/release.sh verify-installed"
        verify_installed_app
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac

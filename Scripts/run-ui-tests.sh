#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ABC_INPUT_SOURCE="com.apple.keylayout.ABC"
MODE="run"

if [[ "${1:-}" == "--preflight-only" ]]; then
    MODE="preflight"
    shift
fi

if [[ $# -ne 0 ]]; then
    echo "usage: Scripts/run-ui-tests.sh [--preflight-only]" >&2
    exit 64
fi

CLASSIFICATION=""
FINAL_STATUS=0
ORIGINAL_INPUT_SOURCE=""
FINAL_REPORTED=0
LOG_PATH=""
RESULT_BUNDLE_PATH=""

resolve_developer_dir() {
    if [[ -n "${CORNERPET_DEVELOPER_DIR:-}" ]]; then
        printf '%s\n' "$CORNERPET_DEVELOPER_DIR"
        return 0
    fi
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        printf '%s\n' "$DEVELOPER_DIR"
        return 0
    fi
    if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
        return 0
    fi
    if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
        printf '%s\n' "/Applications/Xcode-beta.app/Contents/Developer"
        return 0
    fi
    return 1
}

report_final() {
    if [[ "$FINAL_REPORTED" -eq 1 ]]; then
        return
    fi
    FINAL_REPORTED=1
    [[ -n "$LOG_PATH" ]] && echo "CORNERPET_UI_TEST_LOG=$LOG_PATH"
    [[ -n "$RESULT_BUNDLE_PATH" ]] && echo "CORNERPET_UI_TEST_RESULT_BUNDLE=$RESULT_BUNDLE_PATH"
    echo "CORNERPET_UI_TEST_CLASSIFICATION=$CLASSIFICATION"
}

restore_input_source() {
    [[ -n "$ORIGINAL_INPUT_SOURCE" ]] || return 0

    local current
    current="$($INPUT_SOURCE_TOOL current 2>/dev/null)" || return 1
    if [[ "$current" != "$ORIGINAL_INPUT_SOURCE" ]]; then
        "$INPUT_SOURCE_TOOL" select "$ORIGINAL_INPUT_SOURCE" || return 1
    fi

    current="$($INPUT_SOURCE_TOOL current 2>/dev/null)" || return 1
    [[ "$current" == "$ORIGINAL_INPUT_SOURCE" ]]
}

finish() {
    local observed_status=$?
    trap - EXIT INT TERM

    if [[ "$FINAL_STATUS" -eq 0 && "$observed_status" -ne 0 ]]; then
        FINAL_STATUS="$observed_status"
    fi

    if ! restore_input_source; then
        CLASSIFICATION="input-source-restore-failed"
        FINAL_STATUS=74
    fi

    if [[ -z "$CLASSIFICATION" ]]; then
        if [[ "$FINAL_STATUS" -eq 0 ]]; then
            CLASSIFICATION="passed"
        else
            CLASSIFICATION="environment-preflight"
        fi
    fi

    report_final
    exit "$FINAL_STATUS"
}

handle_signal() {
    local signal_number="$1"
    CLASSIFICATION="interrupted"
    FINAL_STATUS=$((128 + signal_number))
    exit "$FINAL_STATUS"
}

trap finish EXIT
trap 'handle_signal 2' INT
trap 'handle_signal 15' TERM

DEVELOPER_DIR_RESOLVED="$(resolve_developer_dir)" || {
    echo "error: no full Xcode developer directory found" >&2
    CLASSIFICATION="environment-preflight"
    FINAL_STATUS=64
    exit "$FINAL_STATUS"
}

XCODEBUILD="${CORNERPET_XCODEBUILD:-$DEVELOPER_DIR_RESOLVED/usr/bin/xcodebuild}"
if [[ ! -x "$XCODEBUILD" ]]; then
    echo "error: xcodebuild is not executable: $XCODEBUILD" >&2
    CLASSIFICATION="environment-preflight"
    FINAL_STATUS=64
    exit "$FINAL_STATUS"
fi

if [[ -n "${CORNERPET_INPUT_SOURCE_TOOL:-}" ]]; then
    INPUT_SOURCE_TOOL="$CORNERPET_INPUT_SOURCE_TOOL"
else
    HELPER_CACHE="${TMPDIR:-/tmp}/cornerpet-ui-automation"
    mkdir -p "$HELPER_CACHE"
    INPUT_SOURCE_TOOL="$HELPER_CACHE/input-source"
    if [[ ! -x "$INPUT_SOURCE_TOOL" || "$SCRIPT_DIR/UIAutomation/InputSource.swift" -nt "$INPUT_SOURCE_TOOL" ]]; then
        if ! DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" xcrun swiftc \
            -framework AppKit \
            -framework Carbon \
            "$SCRIPT_DIR/UIAutomation/InputSource.swift" \
            -o "$INPUT_SOURCE_TOOL"; then
            echo "error: failed to build the input-source helper" >&2
            CLASSIFICATION="environment-preflight"
            FINAL_STATUS=64
            exit "$FINAL_STATUS"
        fi
    fi
fi

if [[ ! -x "$INPUT_SOURCE_TOOL" ]]; then
    echo "error: input-source tool is not executable: $INPUT_SOURCE_TOOL" >&2
    CLASSIFICATION="environment-preflight"
    FINAL_STATUS=64
    exit "$FINAL_STATUS"
fi

ORIGINAL_INPUT_SOURCE="$($INPUT_SOURCE_TOOL current)" || {
    echo "error: unable to read the current input source" >&2
    CLASSIFICATION="environment-preflight"
    FINAL_STATUS=64
    exit "$FINAL_STATUS"
}

echo "CORNERPET_UI_TEST_ORIGINAL_INPUT_SOURCE=$ORIGINAL_INPUT_SOURCE"

if [[ "$ORIGINAL_INPUT_SOURCE" != "$ABC_INPUT_SOURCE" ]]; then
    if ! "$INPUT_SOURCE_TOOL" select "$ABC_INPUT_SOURCE"; then
        echo "error: unable to select the ABC input source" >&2
        CLASSIFICATION="environment-preflight"
        FINAL_STATUS=64
        exit "$FINAL_STATUS"
    fi
fi

ACTIVE_INPUT_SOURCE="$($INPUT_SOURCE_TOOL current)" || {
    echo "error: unable to verify the active input source" >&2
    CLASSIFICATION="environment-preflight"
    FINAL_STATUS=64
    exit "$FINAL_STATUS"
}

if [[ "$ACTIVE_INPUT_SOURCE" != "$ABC_INPUT_SOURCE" ]]; then
    echo "error: ABC input source verification failed: $ACTIVE_INPUT_SOURCE" >&2
    CLASSIFICATION="environment-preflight"
    FINAL_STATUS=64
    exit "$FINAL_STATUS"
fi

echo "CORNERPET_UI_TEST_ACTIVE_INPUT_SOURCE=$ACTIVE_INPUT_SOURCE"

if [[ "$ORIGINAL_INPUT_SOURCE" != "$ABC_INPUT_SOURCE" ]]; then
    if ! "$INPUT_SOURCE_TOOL" quiesce "$ORIGINAL_INPUT_SOURCE"; then
        echo "error: unable to quiesce the inactive input source process" >&2
        CLASSIFICATION="environment-preflight"
        FINAL_STATUS=64
        exit "$FINAL_STATUS"
    fi
    echo "CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE=$ORIGINAL_INPUT_SOURCE"
fi

if [[ "$MODE" == "preflight" ]]; then
    CLASSIFICATION="preflight-passed"
    exit 0
fi

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
EVIDENCE_DIR="${CORNERPET_TEST_EVIDENCE_DIR:-$PROJECT_ROOT/build/test-evidence/$TIMESTAMP}"
mkdir -p "$EVIDENCE_DIR"
LOG_PATH="$EVIDENCE_DIR/CornerPetUITests.log"
RESULT_BUNDLE_PATH="$EVIDENCE_DIR/CornerPetUITests.xcresult"

set +e
DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCODEBUILD" test \
    -project "$PROJECT_ROOT/CornerPet.xcodeproj" \
    -scheme CornerPet \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -parallel-testing-enabled NO \
    -only-testing:CornerPetUITests \
    -resultBundlePath "$RESULT_BUNDLE_PATH" \
    2>&1 | tee "$LOG_PATH"
XCODE_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$XCODE_STATUS" -eq 0 ]]; then
    CLASSIFICATION="passed"
    FINAL_STATUS=0
elif grep -Eiq \
    "failed to (establish|initialize|create|launch).*(automation|session)|automation session|AXError|candidate window|input ?method|UI interruption|UI Testing Failure.*application.*not running" \
    "$LOG_PATH"; then
    CLASSIFICATION="automation-infrastructure"
    FINAL_STATUS=70
else
    CLASSIFICATION="product-regression"
    FINAL_STATUS=65
fi

exit "$FINAL_STATUS"

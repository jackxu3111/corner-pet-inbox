#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ABC_INPUT_SOURCE="com.apple.keylayout.ABC"
MODE="run"

case "${1:-}" in
    --preflight-only)
        MODE="preflight"
        shift
        ;;
    --probe-only)
        MODE="probe"
        shift
        ;;
esac

if [[ $# -ne 0 ]]; then
    echo "usage: Scripts/run-ui-tests.sh [--preflight-only|--probe-only]" >&2
    exit 64
fi

CLASSIFICATION=""
FINAL_STATUS=0
ORIGINAL_INPUT_SOURCE=""
FINAL_REPORTED=0
LOG_PATH=""
RESULT_BUNDLE_PATH=""
QUIESCED_INPUT_SOURCE_STATE=""
INPUT_SOURCE_EXPECTATION_ESTABLISHED=0

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
    [[ "$current" == "$ORIGINAL_INPUT_SOURCE" ]] || return 1

}

finish() {
    local observed_status=$?
    local final_active_input_source=""
    trap - EXIT INT TERM

    if [[ "$FINAL_STATUS" -eq 0 && "$observed_status" -ne 0 ]]; then
        FINAL_STATUS="$observed_status"
    fi

    if [[ "$INPUT_SOURCE_EXPECTATION_ESTABLISHED" -eq 1 ]]; then
        final_active_input_source="$($INPUT_SOURCE_TOOL current 2>/dev/null)" || true
        if [[ "$final_active_input_source" != "$ABC_INPUT_SOURCE" ]]; then
            if [[ "$FINAL_STATUS" -eq 0 ]]; then
                echo "error: input source changed during UI automation: ${final_active_input_source:-unavailable}" >&2
                CLASSIFICATION="input-source-drift"
                FINAL_STATUS=75
            else
                echo "warning: input source changed during UI automation: ${final_active_input_source:-unavailable}" >&2
            fi
        fi
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
echo "CORNERPET_UI_TEST_MODE=$MODE"
INPUT_SOURCE_EXPECTATION_ESTABLISHED=1

if [[ "$ORIGINAL_INPUT_SOURCE" != "$ABC_INPUT_SOURCE" ]]; then
    QUIESCED_INPUT_SOURCE_STATE="$($INPUT_SOURCE_TOOL quiesce "$ORIGINAL_INPUT_SOURCE")" || {
        echo "error: unable to dismiss an inactive input source candidate window" >&2
        CLASSIFICATION="environment-preflight"
        FINAL_STATUS=64
        exit "$FINAL_STATUS"
    }
    if [[ "$QUIESCED_INPUT_SOURCE_STATE" != "escape-posted" &&
          "$QUIESCED_INPUT_SOURCE_STATE" != "unchanged" ]]; then
        echo "error: invalid input source quiesce state: $QUIESCED_INPUT_SOURCE_STATE" >&2
        CLASSIFICATION="environment-preflight"
        FINAL_STATUS=64
        exit "$FINAL_STATUS"
    fi
    echo "CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE=$ORIGINAL_INPUT_SOURCE"
    echo "CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE_STATE=$QUIESCED_INPUT_SOURCE_STATE"
fi

if [[ "$MODE" == "preflight" ]]; then
    CLASSIFICATION="preflight-passed"
    exit 0
fi

AD_HOC_SIGNING=0
case "${CORNERPET_AD_HOC_SIGNING:-0}" in
    0|"")
        ;;
    1)
        AD_HOC_SIGNING=1
        echo "CORNERPET_UI_TEST_SIGNING=ad-hoc"
        ;;
    *)
        echo "error: CORNERPET_AD_HOC_SIGNING must be 0 or 1" >&2
        CLASSIFICATION="environment-preflight"
        FINAL_STATUS=64
        exit "$FINAL_STATUS"
        ;;
esac

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
EVIDENCE_DIR="${CORNERPET_TEST_EVIDENCE_DIR:-$PROJECT_ROOT/build/test-evidence/$TIMESTAMP}"
mkdir -p "$EVIDENCE_DIR"
LOG_PATH="$EVIDENCE_DIR/CornerPetUITests.log"
RESULT_BUNDLE_PATH="$EVIDENCE_DIR/CornerPetUITests.xcresult"

set +e
ONLY_TESTING_TARGET="CornerPetUITests"
if [[ "$MODE" == "probe" ]]; then
    ONLY_TESTING_TARGET="CornerPetUITests/CornerPetLaunchTests/testApplicationLaunchesWithoutMainWindow"
fi

XCODEBUILD_ARGS=(
    test
    -project "$PROJECT_ROOT/CornerPet.xcodeproj"
    -scheme CornerPet
    -configuration Debug
    -destination "platform=macOS,arch=arm64"
    -parallel-testing-enabled NO
    "-only-testing:$ONLY_TESTING_TARGET"
    -resultBundlePath "$RESULT_BUNDLE_PATH"
)
if [[ "$AD_HOC_SIGNING" -eq 1 ]]; then
    XCODEBUILD_ARGS+=(
        "CODE_SIGN_STYLE=Manual"
        "CODE_SIGN_IDENTITY=-"
        "DEVELOPMENT_TEAM="
    )
fi

DEVELOPER_DIR="$DEVELOPER_DIR_RESOLVED" "$XCODEBUILD" "${XCODEBUILD_ARGS[@]}" \
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

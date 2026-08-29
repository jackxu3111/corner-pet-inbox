#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
RUNNER="$PROJECT_ROOT/Scripts/run-ui-tests.sh"
PASS_COUNT=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq "$unexpected" "$file"; then
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
    mkdir -p "$FIXTURE_DIR/Developer" "$FIXTURE_DIR/evidence"
    INPUT_STATE="$FIXTURE_DIR/input-state"
    INPUT_CALLS="$FIXTURE_DIR/input-calls"
    XCODE_ARGS="$FIXTURE_DIR/xcode-args"
    XCODE_OUTPUT="$FIXTURE_DIR/xcode-output"
    RUN_OUTPUT="$FIXTURE_DIR/run-output"

    : > "$INPUT_CALLS"
    : > "$XCODE_OUTPUT"

    cat > "$FIXTURE_DIR/input-source" <<'FAKE_INPUT'
#!/bin/bash
set -u
case "${1:-}" in
    current)
        cat "$FAKE_INPUT_STATE"
        ;;
    select)
        identifier="${2:-}"
        echo "select:$identifier" >> "$FAKE_INPUT_CALLS"
        if [[ "${FAKE_FAIL_SELECT_ID:-}" == "$identifier" ]]; then
            exit 1
        fi
        printf '%s\n' "$identifier" > "$FAKE_INPUT_STATE"
        ;;
    quiesce)
        identifier="${2:-}"
        echo "quiesce:$identifier" >> "$FAKE_INPUT_CALLS"
        if [[ "${FAKE_FAIL_QUIESCE_ID:-}" == "$identifier" ]]; then
            exit 1
        fi
        printf '%s\n' "escape-posted"
        ;;
    *)
        exit 64
        ;;
esac
FAKE_INPUT

    cat > "$FIXTURE_DIR/xcodebuild" <<'FAKE_XCODE'
#!/bin/bash
set -u
printf '%s\n' "$*" > "$FAKE_XCODE_ARGS"
if [[ -n "${FAKE_XCODE_OUTPUT:-}" ]]; then
    printf '%s\n' "$FAKE_XCODE_OUTPUT"
fi
if [[ "${FAKE_XCODE_SIGNAL_PARENT:-0}" == "1" ]]; then
    kill -TERM "$PPID"
    exit 143
fi
if [[ -n "${FAKE_XCODE_DRIFT_INPUT_SOURCE:-}" ]]; then
    printf '%s\n' "$FAKE_XCODE_DRIFT_INPUT_SOURCE" > "$FAKE_INPUT_STATE"
fi
exit "${FAKE_XCODE_EXIT:-0}"
FAKE_XCODE

    chmod +x "$FIXTURE_DIR/input-source" "$FIXTURE_DIR/xcodebuild"
}

cleanup_fixture() {
    rm -rf "$FIXTURE_DIR"
}

run_fixture() {
    set +e
    FAKE_INPUT_STATE="$INPUT_STATE" \
    FAKE_INPUT_CALLS="$INPUT_CALLS" \
    FAKE_FAIL_SELECT_ID="${FAKE_FAIL_SELECT_ID:-}" \
    FAKE_FAIL_QUIESCE_ID="${FAKE_FAIL_QUIESCE_ID:-}" \
    FAKE_XCODE_ARGS="$XCODE_ARGS" \
    FAKE_XCODE_OUTPUT="${FAKE_XCODE_OUTPUT:-}" \
    FAKE_XCODE_EXIT="${FAKE_XCODE_EXIT:-0}" \
    FAKE_XCODE_SIGNAL_PARENT="${FAKE_XCODE_SIGNAL_PARENT:-0}" \
    FAKE_XCODE_DRIFT_INPUT_SOURCE="${FAKE_XCODE_DRIFT_INPUT_SOURCE:-}" \
    CORNERPET_INPUT_SOURCE_TOOL="$FIXTURE_DIR/input-source" \
    CORNERPET_XCODEBUILD="$FIXTURE_DIR/xcodebuild" \
    CORNERPET_DEVELOPER_DIR="$FIXTURE_DIR/Developer" \
    CORNERPET_TEST_EVIDENCE_DIR="$FIXTURE_DIR/evidence" \
    /bin/bash "$RUNNER" > "$RUN_OUTPUT" 2>&1
    RUN_STATUS=$?
    set -e
}

test_abc_does_not_switch() {
    make_fixture
    printf '%s\n' "com.apple.keylayout.ABC" > "$INPUT_STATE"

    run_fixture

    assert_equals "$RUN_STATUS" "0" "ABC run status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.keylayout.ABC" "ABC final input source"
    assert_not_contains "$INPUT_CALLS" "select:"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=passed"
    assert_contains "$XCODE_ARGS" "-parallel-testing-enabled NO"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_switches_and_restores_after_success() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"

    run_fixture

    assert_equals "$RUN_STATUS" "0" "successful run status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.inputmethod.SCIM.ITABC" "restored Chinese input source"
    assert_equals "$(sed -n '1p' "$INPUT_CALLS")" "select:com.apple.keylayout.ABC" "temporary ABC selection"
    assert_equals "$(sed -n '2p' "$INPUT_CALLS")" "quiesce:com.apple.inputmethod.SCIM.ITABC" "inactive input-method cleanup"
    assert_equals "$(sed -n '3p' "$INPUT_CALLS")" "select:com.apple.inputmethod.SCIM.ITABC" "original source restoration"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=passed"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_ACTIVE_INPUT_SOURCE=com.apple.keylayout.ABC"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE=com.apple.inputmethod.SCIM.ITABC"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_QUIESCED_INPUT_SOURCE_STATE=escape-posted"
    cleanup_fixture
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_product_failure_restores_and_preserves_status() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"
    FAKE_XCODE_EXIT=65
    FAKE_XCODE_OUTPUT="XCTAssertEqual failed: product assertion"

    run_fixture

    assert_equals "$RUN_STATUS" "65" "product failure status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.inputmethod.SCIM.ITABC" "product failure restoration"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=product-regression"
    cleanup_fixture
    unset FAKE_XCODE_EXIT FAKE_XCODE_OUTPUT
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_automation_failure_restores_and_uses_infrastructure_status() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"
    FAKE_XCODE_EXIT=65
    FAKE_XCODE_OUTPUT="Failed to establish automation session for application"

    run_fixture

    assert_equals "$RUN_STATUS" "70" "automation failure status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.inputmethod.SCIM.ITABC" "automation failure restoration"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=automation-infrastructure"
    cleanup_fixture
    unset FAKE_XCODE_EXIT FAKE_XCODE_OUTPUT
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_signal_restores_original_source() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"
    FAKE_XCODE_SIGNAL_PARENT=1

    run_fixture

    assert_equals "$RUN_STATUS" "143" "signal status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.inputmethod.SCIM.ITABC" "signal restoration"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=interrupted"
    cleanup_fixture
    unset FAKE_XCODE_SIGNAL_PARENT
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_restore_failure_overrides_status() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"
    FAKE_FAIL_SELECT_ID="com.apple.inputmethod.SCIM.ITABC"

    run_fixture

    assert_equals "$RUN_STATUS" "74" "restore failure status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.keylayout.ABC" "failed restore leaves observed source"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=input-source-restore-failed"
    cleanup_fixture
    unset FAKE_FAIL_SELECT_ID
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_input_source_drift_visible_at_suite_end_overrides_success() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"
    FAKE_XCODE_DRIFT_INPUT_SOURCE="com.apple.inputmethod.SCIM.ITABC"

    run_fixture

    assert_equals "$RUN_STATUS" "75" "input-source drift status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.inputmethod.SCIM.ITABC" "drift restoration"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=input-source-drift"
    cleanup_fixture
    unset FAKE_XCODE_DRIFT_INPUT_SOURCE
    PASS_COUNT=$((PASS_COUNT + 1))
}

test_quiesce_failure_stops_before_xcode_and_restores() {
    make_fixture
    printf '%s\n' "com.apple.inputmethod.SCIM.ITABC" > "$INPUT_STATE"
    FAKE_FAIL_QUIESCE_ID="com.apple.inputmethod.SCIM.ITABC"

    run_fixture

    assert_equals "$RUN_STATUS" "64" "quiesce failure status"
    assert_equals "$(cat "$INPUT_STATE")" "com.apple.inputmethod.SCIM.ITABC" "quiesce failure restoration"
    assert_contains "$RUN_OUTPUT" "CORNERPET_UI_TEST_CLASSIFICATION=environment-preflight"
    [[ ! -s "$XCODE_ARGS" ]] || fail "xcodebuild ran after quiesce failed"
    cleanup_fixture
    unset FAKE_FAIL_QUIESCE_ID
    PASS_COUNT=$((PASS_COUNT + 1))
}

set -e
[[ -f "$RUNNER" ]] || fail "missing runner: $RUNNER"

test_abc_does_not_switch
test_switches_and_restores_after_success
test_product_failure_restores_and_preserves_status
test_automation_failure_restores_and_uses_infrastructure_status
test_signal_restores_original_source
test_restore_failure_overrides_status
test_input_source_drift_visible_at_suite_end_overrides_success
test_quiesce_failure_stops_before_xcode_and_restores

echo "PASS: $PASS_COUNT UI automation runner tests"

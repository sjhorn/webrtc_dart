#!/bin/bash
# Run All Tests - Executes all automated browser tests
#
# Usage:
#   ./run_all_tests.sh [browser]
#   BROWSER=firefox ./run_all_tests.sh
#
# Examples:
#   ./run_all_tests.sh chrome    # Run all tests with Chrome
#   ./run_all_tests.sh           # Defaults to Chrome

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROWSER="${1:-${BROWSER:-chrome}}"
LOG_FILE="$SCRIPT_DIR/test_results.log"

# Clear log file
> "$LOG_FILE"

# Function to log and print
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

# Core tests (most reliable, run first)
CORE_TESTS="browser ice_trickle ice_restart datachannel_answer"

# Media tests
MEDIA_TESTS="media_sendonly media_recvonly media_sendrecv media_answer sendrecv_answer"

# Save to disk tests
SAVE_TESTS="save_to_disk save_to_disk_h264 save_to_disk_vp9 save_to_disk_opus save_to_disk_av save_to_disk_av1"

# Advanced feature tests
ADVANCED_TESTS="simulcast twcc rtx"

# Multi-client tests (take longer)
MULTI_TESTS="multi_client multi_client_sendonly multi_client_recvonly multi_client_sendrecv"

# All tests combined
ALL_TESTS="$CORE_TESTS $MEDIA_TESTS $SAVE_TESTS $ADVANCED_TESTS $MULTI_TESTS"

log "========================================"
log "Running All Automated Tests"
log "========================================"
log "Browser: $BROWSER"
log "Tests: $(echo $ALL_TESTS | wc -w | tr -d ' ') total"
log "Log file: $LOG_FILE"
log ""

passed=0
failed=0
skipped=0
failed_tests=""

cd "$SCRIPT_DIR"

for test in $ALL_TESTS; do
    log "----------------------------------------"
    log "Running: $test"
    log "----------------------------------------"

    # Brief delay to ensure previous test cleaned up (helps with Safari port reuse)
    sleep 1

    # Run the test and capture output
    output=$(./run_test.sh "$test" "$BROWSER" 2>&1)
    exit_code=$?

    # Check result
    if [ $exit_code -eq 0 ]; then
        log "+ PASS: $test"
        passed=$((passed + 1))
    elif echo "$output" | grep -q "Skipped\|SKIP"; then
        log "- SKIP: $test"
        skipped=$((skipped + 1))
    else
        log "x FAIL: $test"
        failed=$((failed + 1))
        failed_tests="$failed_tests $test"
        # Show error in log
        echo "$output" | grep -E "Error:|error:" | head -3 >> "$LOG_FILE"
        echo "$output" | grep -E "Error:|error:" | head -3
    fi
    log ""
done

log "========================================"
log "SUMMARY"
log "========================================"
log "Passed:  $passed"
log "Failed:  $failed"
log "Skipped: $skipped"
log "Total:   $((passed + failed + skipped))"

if [ -n "$failed_tests" ]; then
    log ""
    log "Failed tests:$failed_tests"
fi

log "========================================"

if [ $failed -eq 0 ]; then
    log "All tests passed!"
    exit 0
else
    log "Some tests failed!"
    exit 1
fi

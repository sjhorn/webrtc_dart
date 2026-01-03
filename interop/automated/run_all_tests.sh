#!/bin/bash
# Run All Tests in Parallel
#
# Usage:
#   ./run_all_tests.sh [browser] [max_parallel]
#
# Examples:
#   ./run_all_tests.sh chrome      # Run with 8 parallel tests (default)
#   ./run_all_tests.sh chrome 4    # Run with 4 parallel tests
#   ./run_all_tests.sh firefox 6   # Firefox with 6 parallel

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BROWSER="${1:-${BROWSER:-chrome}}"
MAX_PARALLEL="${2:-8}"
LOG_FILE="$SCRIPT_DIR/test_results.log"
TMP_DIR=$(mktemp -d)

export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:$PATH"
export BROWSER
export TMP_DIR
export SCRIPT_DIR

ALL_TESTS="browser ice_trickle ice_restart datachannel_answer media_sendonly media_recvonly media_sendrecv media_answer sendrecv_answer save_to_disk save_to_disk_h264 save_to_disk_vp9 save_to_disk_opus save_to_disk_av save_to_disk_av1 simulcast twcc rtx dtmf multi_client multi_client_sendonly multi_client_recvonly multi_client_sendrecv"

echo "========================================"
echo "Running All Tests (Parallel)"
echo "========================================"
echo "Browser: $BROWSER"
echo "Parallel: $MAX_PARALLEL"
echo "Tests: $(echo $ALL_TESTS | wc -w | tr -d ' ') total"
echo ""

> "$LOG_FILE"

run_test() {
  local test_name=$1
  cd "$SCRIPT_DIR"
  if ./run_test.sh "$test_name" "$BROWSER" > "$TMP_DIR/$test_name.log" 2>&1; then
    echo "PASS" > "$TMP_DIR/$test_name.result"
  else
    echo "FAIL" > "$TMP_DIR/$test_name.result"
  fi
}
export -f run_test

start_time=$(date +%s)

# Run all tests in parallel
echo $ALL_TESTS | tr ' ' '\n' | xargs -P $MAX_PARALLEL -I {} bash -c 'run_test "$@"' _ {}

end_time=$(date +%s)
duration=$((end_time - start_time))

# Collect results
passed=0
failed=0
failed_tests=""

for test in $ALL_TESTS; do
  result_file="$TMP_DIR/$test.result"
  if [ -f "$result_file" ] && [ "$(cat "$result_file")" = "PASS" ]; then
    echo "+ PASS: $test" | tee -a "$LOG_FILE"
    passed=$((passed + 1))
  else
    echo "x FAIL: $test" | tee -a "$LOG_FILE"
    failed=$((failed + 1))
    failed_tests="$failed_tests $test"
    grep -E "Error:|error:|FAIL" "$TMP_DIR/$test.log" 2>/dev/null | head -2
  fi
done

# Clean up recording files
cd "$SCRIPT_DIR/../.."
rm -f recording-*.webm 2>/dev/null

# Keep logs on failure for debugging
if [ $failed -gt 0 ]; then
  echo "Logs saved to: $TMP_DIR"
else
  rm -rf "$TMP_DIR"
fi

echo ""
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Passed:  $passed"
echo "Failed:  $failed"
echo "Total:   $((passed + failed))"
echo "Time:    ${duration}s"
[ -n "$failed_tests" ] && echo "Failed:$failed_tests"
echo "========================================"

[ $failed -eq 0 ] && echo "All tests passed!" && exit 0
echo "Some tests failed!" && exit 1

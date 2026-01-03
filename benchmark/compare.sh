#!/bin/bash
# Compare webrtc_dart vs werift performance
#
# Usage: ./benchmark/compare.sh
#
# Runs both Dart and werift benchmarks and displays comparison.

set -e

SCRIPT_DIR="$(dirname "$0")"

# Change to project root
cd "$SCRIPT_DIR/.."

echo "webrtc_dart vs werift Performance Comparison"
echo "============================================================"

# Run Dart performance tests
echo ""
echo ">>> Running webrtc_dart benchmarks..."
dart test test/performance/ 2>&1 | grep -E "PERF OK|PERF WARNING" | head -20

echo ""
echo ">>> Running werift benchmarks..."
"$SCRIPT_DIR/run_werift_benchmarks.sh" 2>&1 | grep -E "Ops/second:" | head -20

echo ""
echo "============================================================"
echo "Comparison complete. See above for results."

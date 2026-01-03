#!/bin/bash
# Run all performance tests
#
# Usage: ./benchmark/run_perf_tests.sh

set -e

# Change to project root
cd "$(dirname "$0")/.."

echo "Running webrtc_dart Performance Tests"
echo "============================================================"

dart test test/performance/ "$@"

#!/bin/bash
# Run werift benchmarks for comparison
#
# Usage: ./benchmark/run_werift_benchmarks.sh

set -e

cd "$(dirname "$0")/werift"

# Ensure PATH includes node
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"

echo "Running werift Benchmarks"
echo "============================================================"

echo ""
echo "=== SRTP ==="
node srtp_bench.mjs

echo ""
echo "=== RTP ==="
node rtp_bench.mjs

echo ""
echo "=== STUN ==="
node stun_bench.mjs

echo ""
echo "=== SDP ==="
node sdp_bench.mjs

echo ""
echo "=== H.264 ==="
node h264_bench.mjs

echo ""
echo "=== ICE Candidate ==="
node ice_bench.mjs

echo ""
echo "============================================================"
echo "All werift benchmarks complete"

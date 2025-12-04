#!/bin/bash
# Automated Browser Interop Test Runner
#
# Usage:
#   ./run_browser_tests.sh [chrome|firefox|webkit|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BROWSER="${1:-all}"
SERVER_PORT=8765
SERVER_PID=""

echo "========================================"
echo "WebRTC Browser Interop Test"
echo "========================================"
echo "Project root: $PROJECT_ROOT"
echo "Browser: $BROWSER"
echo ""

# Function to cleanup on exit
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        echo "Stopping Dart server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Start Dart signaling server in background
echo "Starting Dart signaling server..."
cd "$PROJECT_ROOT"
dart run interop/automated/dart_signaling_server.dart &
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to start..."
sleep 2

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ERROR: Dart server failed to start!"
    exit 1
fi

# Check server is responding
for i in {1..10}; do
    if curl -s "http://localhost:$SERVER_PORT/status" > /dev/null 2>&1; then
        echo "Server is ready!"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "ERROR: Server not responding after 10 seconds"
        exit 1
    fi
    sleep 1
done

# Run Playwright tests
echo ""
echo "Running browser tests..."
cd "$SCRIPT_DIR/.."
node automated/browser_test.mjs "$BROWSER"
TEST_EXIT_CODE=$?

echo ""
echo "Tests completed with exit code: $TEST_EXIT_CODE"
exit $TEST_EXIT_CODE

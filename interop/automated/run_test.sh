#!/bin/bash
# Generic Automated Test Runner
#
# Runs a single test with its corresponding Dart server.
# Handles server startup, test execution with timeout, and cleanup.
#
# Usage:
#   ./run_test.sh <test_name> [browser]
#   BROWSER=firefox ./run_test.sh <test_name>
#
# Examples:
#   ./run_test.sh browser chrome
#   ./run_test.sh ice_trickle firefox
#   ./run_test.sh media_sendonly
#   BROWSER=safari ./run_test.sh save_to_disk
#
# The test name maps to:
#   - Server: <test_name>_server.dart
#   - Test:   <test_name>_test.mjs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Ensure node is available (macOS homebrew path)
export PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:$PATH"

# Configuration
SERVER_STARTUP_TIMEOUT=30   # seconds to wait for server (dart compiles on first run)
TEST_TIMEOUT=120            # seconds for test execution (2 minutes)
CLEANUP_TIMEOUT=5           # seconds to wait for cleanup

# Parse arguments
TEST_NAME="${1:-}"
BROWSER_ARG="${2:-${BROWSER:-chrome}}"

if [ -z "$TEST_NAME" ]; then
    echo "Usage: $0 <test_name> [browser]"
    echo ""
    echo "Examples:"
    echo "  $0 browser chrome"
    echo "  $0 ice_trickle firefox"
    echo "  $0 media_sendonly safari"
    echo "  BROWSER=firefox $0 save_to_disk"
    echo ""
    echo "Available tests:"
    ls -1 "$SCRIPT_DIR"/*_test.mjs 2>/dev/null | xargs -n1 basename | sed 's/_test\.mjs$//' | sort | column
    exit 1
fi

# Determine server and test files
SERVER_FILE="$SCRIPT_DIR/${TEST_NAME}_server.dart"
TEST_FILE="$SCRIPT_DIR/${TEST_NAME}_test.mjs"

# Special case: browser_test uses dart_signaling_server
if [ "$TEST_NAME" = "browser" ]; then
    SERVER_FILE="$SCRIPT_DIR/dart_signaling_server.dart"
fi

# Validate files exist
if [ ! -f "$SERVER_FILE" ]; then
    echo "ERROR: Server file not found: $SERVER_FILE"
    exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: Test file not found: $TEST_FILE"
    exit 1
fi

# Extract port from test file
PORT=$(grep -o "localhost:[0-9]*" "$TEST_FILE" | head -1 | cut -d: -f2)
if [ -z "$PORT" ]; then
    echo "ERROR: Could not determine port from $TEST_FILE"
    exit 1
fi

SERVER_PID=""
TEST_EXIT_CODE=1

# Cleanup function
cleanup() {
    local exit_code=$?

    # Kill server if running
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo "[Cleanup] Stopping server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true

        # Wait briefly for graceful shutdown
        for i in $(seq 1 $CLEANUP_TIMEOUT); do
            if ! kill -0 $SERVER_PID 2>/dev/null; then
                break
            fi
            sleep 1
        done

        # Force kill if still running
        if kill -0 $SERVER_PID 2>/dev/null; then
            echo "[Cleanup] Force killing server..."
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
    fi

    # Kill any orphaned Dart processes on our port
    local orphan_pids=$(lsof -ti :$PORT 2>/dev/null || true)
    if [ -n "$orphan_pids" ]; then
        echo "[Cleanup] Killing orphaned processes on port $PORT..."
        echo "$orphan_pids" | xargs kill -9 2>/dev/null || true
    fi

    # Kill any orphaned ffmpeg processes (from sendonly tests)
    local ffmpeg_pids=$(pgrep -f "ffmpeg.*testsrc" 2>/dev/null || true)
    if [ -n "$ffmpeg_pids" ]; then
        echo "[Cleanup] Killing orphaned ffmpeg processes..."
        echo "$ffmpeg_pids" | xargs kill 2>/dev/null || true
    fi

    # Return appropriate exit code
    if [ $exit_code -ne 0 ]; then
        exit $exit_code
    fi
    exit $TEST_EXIT_CODE
}
trap cleanup EXIT INT TERM

echo "========================================"
echo "Test: $TEST_NAME"
echo "========================================"
echo "Server: $(basename "$SERVER_FILE")"
echo "Test:   $(basename "$TEST_FILE")"
echo "Port:   $PORT"
echo "Browser: $BROWSER_ARG"
echo ""

# Check if port is already in use
if lsof -ti :$PORT >/dev/null 2>&1; then
    echo "WARNING: Port $PORT is already in use"
    echo "Killing existing processes..."
    lsof -ti :$PORT | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# Start Dart server in background
echo "[Server] Starting $(basename "$SERVER_FILE")..."
cd "$PROJECT_ROOT"
dart run "$SERVER_FILE" &
SERVER_PID=$!

# Wait for server to start with timeout
echo "[Server] Waiting for server to be ready (timeout: ${SERVER_STARTUP_TIMEOUT}s)..."
server_ready=false
for i in $(seq 1 $SERVER_STARTUP_TIMEOUT); do
    # Check if server process is still running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "ERROR: Server process died unexpectedly"
        wait $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    # Check if server is responding
    if curl -s "http://localhost:$PORT/status" > /dev/null 2>&1; then
        echo "[Server] Ready on port $PORT"
        server_ready=true
        break
    fi

    sleep 1
done

if [ "$server_ready" = false ]; then
    echo "ERROR: Server not responding after ${SERVER_STARTUP_TIMEOUT} seconds"
    exit 1
fi

# Run the test with timeout
echo ""
echo "[Test] Running $(basename "$TEST_FILE") (timeout: ${TEST_TIMEOUT}s)..."
cd "$SCRIPT_DIR"

# Record start time for cleanup
TEST_START_TIME=$(date +%s)

# Use timeout command to limit test execution
if timeout $TEST_TIMEOUT node "$TEST_FILE" "$BROWSER_ARG"; then
    TEST_EXIT_CODE=0
    echo ""
    echo "[Result] PASSED"

    # Clean up webm files created during this test (only on success)
    cd "$PROJECT_ROOT"
    webm_count=0
    for f in recording-*.webm; do
        if [ -f "$f" ]; then
            file_time=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
            if [ -n "$file_time" ] && [ "$file_time" -ge "$TEST_START_TIME" ]; then
                rm -f "$f"
                webm_count=$((webm_count + 1))
            fi
        fi
    done
    if [ $webm_count -gt 0 ]; then
        echo "[Cleanup] Removed $webm_count recording file(s)"
    fi
else
    TEST_EXIT_CODE=$?
    if [ $TEST_EXIT_CODE -eq 124 ]; then
        echo ""
        echo "[Result] TIMEOUT after ${TEST_TIMEOUT} seconds"
    else
        echo ""
        echo "[Result] FAILED (exit code: $TEST_EXIT_CODE)"
    fi
fi

exit $TEST_EXIT_CODE

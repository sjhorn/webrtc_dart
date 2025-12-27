#!/bin/bash
# Check SDP Output - Dumps the SDP from a test server for debugging
#
# Usage:
#   ./check_sdp.sh <test_name>
#
# Examples:
#   ./check_sdp.sh save_to_disk
#   ./check_sdp.sh media_sendonly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_NAME="${1:-save_to_disk}"
SERVER_FILE="$SCRIPT_DIR/${TEST_NAME}_server.dart"
TEST_FILE="$SCRIPT_DIR/${TEST_NAME}_test.mjs"

# Special case: browser_test uses dart_signaling_server
if [ "$TEST_NAME" = "browser" ]; then
    SERVER_FILE="$SCRIPT_DIR/dart_signaling_server.dart"
fi

if [ ! -f "$SERVER_FILE" ]; then
    echo "ERROR: Server file not found: $SERVER_FILE"
    exit 1
fi

# Extract port from test file
PORT=$(grep -o "localhost:[0-9]*" "$TEST_FILE" 2>/dev/null | head -1 | cut -d: -f2)
if [ -z "$PORT" ]; then
    PORT=8769  # Default
fi

# Kill any existing processes
"$SCRIPT_DIR/stop_test.sh" "$TEST_NAME" 2>/dev/null

echo "Starting $TEST_NAME server on port $PORT..."
cd "$PROJECT_ROOT"
timeout 15 dart run "$SERVER_FILE" &
SERVER_PID=$!
sleep 3

# Start a session
curl -s "http://localhost:$PORT/start" > /dev/null 2>&1
sleep 1

# Get the offer SDP
echo ""
echo "=== SDP Offer ==="
SDP_JSON=$(curl -s "http://localhost:$PORT/offer" 2>/dev/null)

if [ -z "$SDP_JSON" ]; then
    echo "ERROR: No SDP returned"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

# Parse and display SDP (using python for JSON parsing)
echo "$SDP_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    sdp = data.get('sdp', '')
    for line in sdp.replace('\r\n', '\n').split('\n'):
        if line:
            print(line)
except Exception as e:
    print(f'Parse error: {e}')
    sys.exit(1)
" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Raw JSON:"
    echo "$SDP_JSON"
fi

echo ""
echo "=== Key Lines (m=, a=rtpmap) ==="
echo "$SDP_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    sdp = data.get('sdp', '')
    for line in sdp.replace('\r\n', '\n').split('\n'):
        if line.startswith('m=') or line.startswith('a=rtpmap'):
            print(line)
except:
    pass
" 2>/dev/null

# Cleanup
echo ""
kill $SERVER_PID 2>/dev/null
"$SCRIPT_DIR/stop_test.sh" "$TEST_NAME" 2>/dev/null
echo "Done."

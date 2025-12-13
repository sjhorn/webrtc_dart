#!/bin/bash
#
# Ring Video Browser Test Script
#
# Starts the Dart server, waits for Ring connection, runs Playwright browser test.
#
# Usage: ./run_browser_test.sh [chrome|safari|all]
#
# Prerequisites:
#   - .env file with RING_REFRESH_TOKEN in example/ring/
#   - npm dependencies installed in interop/ (npm install)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BROWSER="${1:-chrome}"
DART_PID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[Test]${NC} $1"; }
warn() { echo -e "${YELLOW}[Warn]${NC} $1"; }
error() { echo -e "${RED}[Error]${NC} $1"; }

cleanup() {
    if [ -n "$DART_PID" ]; then
        log "Stopping Dart server (PID $DART_PID)..."
        kill $DART_PID 2>/dev/null || true
        wait $DART_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Check prerequisites
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    error ".env file not found in $SCRIPT_DIR"
    error "Create .env with: RING_REFRESH_TOKEN=your_token"
    exit 1
fi

if [ ! -d "$PROJECT_ROOT/interop/node_modules" ]; then
    warn "node_modules not found in interop/, running npm install..."
    cd "$PROJECT_ROOT/interop" && npm install
fi

# Kill any existing server on port 8080
log "Checking for existing servers on port 8080/8888..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:8888 | xargs kill -9 2>/dev/null || true
sleep 1

# Start Dart server
log "Starting Dart server..."
cd "$SCRIPT_DIR"
source .env
dart run recv-via-webrtc.dart > /tmp/ring_server.log 2>&1 &
DART_PID=$!
log "Dart server started with PID $DART_PID"

# Wait for server to start (check HTTP endpoint)
log "Waiting for server to start..."
for i in {1..15}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        log "HTTP server is ready"
        break
    fi
    if [ $i -eq 15 ]; then
        error "Server failed to start. Check /tmp/ring_server.log"
        tail -50 /tmp/ring_server.log
        exit 1
    fi
    sleep 1
done

# Wait for Ring connection (check status endpoint)
log "Waiting for Ring camera connection..."
RING_CONNECTED=false
for i in {1..45}; do
    STATUS=$(curl -s http://localhost:8080/status 2>/dev/null || echo '{}')

    if echo "$STATUS" | grep -q '"ringReceivingVideo":true'; then
        PACKETS=$(echo "$STATUS" | grep -o '"rtpPacketsReceived":[0-9]*' | grep -o '[0-9]*')
        log "Ring camera streaming video ($PACKETS packets received)"
        RING_CONNECTED=true
        break
    fi

    if echo "$STATUS" | grep -q '"ringConnected":true'; then
        log "Ring connected, waiting for video... ($i/45)"
    else
        log "Connecting to Ring... ($i/45)"
    fi

    sleep 1
done

if [ "$RING_CONNECTED" != "true" ]; then
    error "Ring camera did not connect within 45 seconds"
    error "Server log tail:"
    tail -30 /tmp/ring_server.log
    exit 1
fi

# Show status
log "Server status:"
curl -s http://localhost:8080/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/status
echo ""

# Run browser test
log "Running Playwright browser test ($BROWSER)..."
cd "$PROJECT_ROOT/interop"
node automated/ring_video_test.mjs "$BROWSER"
TEST_RESULT=$?

# Show server log tail
log "Server log (last 30 lines):"
tail -30 /tmp/ring_server.log

exit $TEST_RESULT

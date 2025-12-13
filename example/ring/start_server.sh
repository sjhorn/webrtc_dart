#!/bin/bash
#
# Start Ring Video Server for manual browser testing
#
# Usage: ./start_server.sh
#
# Then open http://localhost:8080 in your browser
# Press Ctrl+C to stop
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check .env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${RED}[Error]${NC} .env file not found"
    echo "Create .env with: RING_REFRESH_TOKEN=your_token"
    exit 1
fi

# Kill existing servers
echo -e "${GREEN}[Server]${NC} Checking for existing servers..."
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:8888 | xargs kill -9 2>/dev/null || true
sleep 1

cd "$SCRIPT_DIR"
source .env

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Ring Video Streaming Server${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  Open in browser: ${YELLOW}http://localhost:8080${NC}"
echo ""
echo -e "  Press ${RED}Ctrl+C${NC} to stop"
echo ""
echo -e "${GREEN}========================================${NC}"
echo ""

dart run recv-via-webrtc.dart

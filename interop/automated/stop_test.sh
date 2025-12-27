#!/bin/bash
# Stop Test - Kills orphaned test processes
#
# Cleans up any Dart servers or browser processes left running from tests.
# Useful when a test crashes or you need to force cleanup.
#
# Usage:
#   ./stop_test.sh              # Kill all test-related processes
#   ./stop_test.sh <test_name>  # Kill processes for specific test (by port)
#
# Examples:
#   ./stop_test.sh              # Kill everything
#   ./stop_test.sh browser      # Kill only port 8765
#   ./stop_test.sh ice_trickle  # Kill only port 8781

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# All known test ports (range 8765-8888)
ALL_PORTS="8765 8766 8767 8768 8769 8770 8771 8772 8773 8774 8775 8776 8777 8778 8779 8780 8781 8782 8783 8791 8792 8793 8794 8888"

get_port_for_test() {
    local test=$1
    case "$test" in
        browser) echo 8765 ;;
        datachannel_answer) echo 8775 ;;
        ice_trickle) echo 8781 ;;
        ice_restart) echo 8782 ;;
        media_sendonly|rtp_forward) echo 8766 ;;
        media_recvonly) echo 8767 ;;
        media_sendrecv) echo 8768 ;;
        media_answer|save_to_disk_av1) echo 8776 ;;
        sendrecv_answer|save_to_disk_gst) echo 8777 ;;
        save_to_disk) echo 8769 ;;
        save_to_disk_h264) echo 8770 ;;
        save_to_disk_vp9|save_to_disk_mp4) echo 8771 ;;
        save_to_disk_opus|save_to_disk_mp4_av) echo 8772 ;;
        save_to_disk_av|save_to_disk_mp4_opus) echo 8773 ;;
        save_to_disk_packetloss|save_to_disk_dump) echo 8774 ;;
        save_to_disk_dtx) echo 8775 ;;
        simulcast) echo 8780 ;;
        simulcast_sfu) echo 8781 ;;
        twcc) echo 8779 ;;
        rtx|red_sendrecv) echo 8778 ;;
        multi_client) echo 8783 ;;
        multi_client_sendonly) echo 8791 ;;
        multi_client_recvonly) echo 8792 ;;
        multi_client_sendrecv) echo 8793 ;;
        interop_server) echo 8794 ;;
        pubsub*) echo 8888 ;;
        *) echo "" ;;
    esac
}

kill_port() {
    local port=$1
    local pids=$(lsof -ti :$port 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "Killing processes on port $port: $pids"
        echo "$pids" | xargs kill -9 2>/dev/null || true
        return 0
    fi
    return 1
}

kill_dart_servers() {
    local pids=$(pgrep -f "_server\.dart" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "Killing Dart server processes: $pids"
        echo "$pids" | xargs kill -9 2>/dev/null || true
        return 0
    fi
    return 1
}

TEST_NAME="${1:-}"

if [ -n "$TEST_NAME" ]; then
    # Kill specific test
    port=$(get_port_for_test "$TEST_NAME")
    if [ -z "$port" ]; then
        echo "Unknown test: $TEST_NAME"
        echo ""
        echo "Usage: $0 [test_name]"
        echo ""
        echo "Run without arguments to kill all test processes."
        echo "Or specify a test name to kill only that test's port."
        exit 1
    fi

    echo "Stopping test: $TEST_NAME (port $port)"
    if kill_port $port; then
        echo "Done."
    else
        echo "No processes found on port $port"
    fi
else
    # Kill all test-related processes
    echo "Stopping all test processes..."
    echo ""

    killed=0

    # Kill by known ports
    for port in $ALL_PORTS; do
        if kill_port $port 2>/dev/null; then
            killed=$((killed + 1))
        fi
    done

    # Kill any remaining dart servers
    if kill_dart_servers; then
        killed=$((killed + 1))
    fi

    if [ $killed -eq 0 ]; then
        echo "No test processes found."
    else
        echo ""
        echo "Cleanup complete."
    fi
fi

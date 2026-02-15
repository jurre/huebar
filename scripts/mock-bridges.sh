#!/usr/bin/env bash
set -euo pipefail

# scripts/mock-bridges.sh — Spin up mock Hue bridges for UI testing
#
# Usage:
#   ./scripts/mock-bridges.sh          # start bridges
#   ./scripts/mock-bridges.sh stop     # stop all mock bridges

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PIDS=()

cleanup() {
    echo ""
    echo "Stopping mock bridges..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null
    echo "Done."
}

# If "stop" argument, kill any running mock bridges
if [[ "${1:-}" == "stop" ]]; then
    pkill -f HueMockBridge 2>/dev/null && echo "Stopped mock bridges." || echo "No mock bridges running."
    exit 0
fi

trap cleanup EXIT INT TERM

# Kill any leftover mock bridges from previous runs
pgrep -f HueMockBridge | xargs kill 2>/dev/null || true
sleep 0.5

echo "Building HueMockBridge..."
cd "$PROJECT_DIR"
swift build --product HueMockBridge --quiet

BINARY="$(swift build --product HueMockBridge --show-bin-path)/HueMockBridge"

echo ""
echo "Starting mock bridges..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Bridge 1: Upstairs — typical home setup
"$BINARY" \
    --port 8080 \
    --name "Upstairs" \
    --rooms "Living Room:living_room:4,Bedroom:bedroom:2,Bathroom:bathroom:1" &
PIDS+=($!)
sleep 0.5

# Bridge 2: Downstairs — different rooms
"$BINARY" \
    --port 8081 \
    --name "Downstairs" \
    --rooms "Kitchen:kitchen:3,Dining Room:dining:2,Hallway:hallway:1,Garage:garage:2" &
PIDS+=($!)
sleep 0.5

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Mock bridges running! To connect from HueBar:"
echo "  1. Open HueBar setup (or sign out first)"
echo "  2. Enter 127.0.0.1:8080 as manual IP → pair"
echo "  3. Enter 127.0.0.1:8081 as manual IP → pair"
echo ""
echo "Press Ctrl+C to stop all bridges."

wait

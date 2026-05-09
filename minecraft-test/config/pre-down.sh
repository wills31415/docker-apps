#!/usr/bin/env bash
# =============================================================================
# Hook pre-down : tue le watcher dynmap-auto-render avant l'arrêt du cluster.
# =============================================================================
set -e
echo "🧪 [pre-down test] Arrêt du serveur test..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCHER_PID_FILE="$SCRIPT_DIR/../shared/dynmap-auto-render.pid"
if [ -f "$WATCHER_PID_FILE" ]; then
    pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        echo "🔁 [pre-down test] Watcher dynmap-auto-render arrêté (PID $pid)."
    fi
    rm -f "$WATCHER_PID_FILE"
fi

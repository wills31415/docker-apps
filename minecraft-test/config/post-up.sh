#!/usr/bin/env bash
# =============================================================================
# Hook post-up : affiche les infos de connexion. Pas de watcher.
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Lecture .env + .env.local
for env_file in "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.local"; do
    if [ -f "$env_file" ]; then
        set -a
        source <(grep -v '^\s*#' "$env_file" | grep -v '^\s*$')
        set +a
    fi
done

# IP LAN principale
LAN_IP=$(ip -4 addr show | grep -oP '(?<=inet )192\.168\.\d+\.\d+(?=/)' | head -1)
LAN_IP=${LAN_IP:-<ip-de-l-hote>}

RCON_PASSWORD="${RCON_PASSWORD:-changeme-rcon-test}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🧪 Cluster Minecraft TEST démarré (Creative)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🟢 Connexion (LAN uniquement, pas de NAT)"
echo "     Depuis cette machine : localhost:25567"
echo "     Depuis SteamDeck/LAN : ${LAN_IP}:25567"
echo ""
echo "  🔧 RCON (admin local uniquement)"
echo "     docker exec -it minecraft_test rcon-cli"
echo "     docker exec minecraft_test rcon-cli \"<cmd>\""
echo ""
echo "  💡 Mode : Creative · Difficulty : Peaceful · Command blocks : ON"
echo "  💡 Le test partage le pack courant de prod (recopie auto au pre-up)."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Watcher dynmap-auto-render (pour la web map test) ----------------------
# Réutilise le script du cluster prod, override CONTAINER + OVERWORLD_WORLD.
WATCHER_SCRIPT="$SCRIPT_DIR/../../minecraft-server/config/dynmap-auto-render.sh"
WATCHER_PID_FILE="$SCRIPT_DIR/../shared/dynmap-auto-render.pid"
WATCHER_LOG_FILE="$SCRIPT_DIR/../shared/dynmap-auto-render.log"
LEVEL="${LEVEL:-world}"

if [ -f "$WATCHER_PID_FILE" ]; then
    old_pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null || true)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
    fi
    rm -f "$WATCHER_PID_FILE"
fi

if [ -x "$WATCHER_SCRIPT" ]; then
    CONTAINER=minecraft_test OVERWORLD_WORLD="$LEVEL" \
        nohup "$WATCHER_SCRIPT" >> "$WATCHER_LOG_FILE" 2>&1 &
    echo $! > "$WATCHER_PID_FILE"
    disown
    echo "🔁 [post-up test] Watcher dynmap-auto-render démarré (PID $(cat "$WATCHER_PID_FILE"))."
    echo "   Logs : minecraft-test/shared/dynmap-auto-render.log"
    echo ""
fi

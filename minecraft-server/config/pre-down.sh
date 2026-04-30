#!/usr/bin/env bash
# =============================================================================
# Hook : pre-down.sh
# Exécuté AVANT "docker compose down" par la commande "da down minecraft-server".
#
# Rôle : sauvegarder le monde et prévenir les joueurs avant l'arrêt.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "⚠️  [pre-down] Arrêt du serveur Minecraft en cours..."

# --- Stopper le watcher dynmap-auto-render -----------------------------------
WATCHER_PID_FILE="$SCRIPT_DIR/../shared/dynmap-auto-render.pid"
if [ -f "$WATCHER_PID_FILE" ]; then
    watcher_pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null || true)
    if [ -n "$watcher_pid" ] && kill -0 "$watcher_pid" 2>/dev/null; then
        kill "$watcher_pid" 2>/dev/null || true
        echo "🔁 [pre-down] Watcher dynmap-auto-render arrêté (PID $watcher_pid)."
    fi
    rm -f "$WATCHER_PID_FILE"
fi

# --- Stopper le watcher dynmap-grave-marker ----------------------------------
GRAVE_PID_FILE="$SCRIPT_DIR/../shared/dynmap-grave-marker.pid"
if [ -f "$GRAVE_PID_FILE" ]; then
    grave_pid=$(cat "$GRAVE_PID_FILE" 2>/dev/null || true)
    if [ -n "$grave_pid" ] && kill -0 "$grave_pid" 2>/dev/null; then
        kill "$grave_pid" 2>/dev/null || true
        echo "🪦 [pre-down] Watcher dynmap-grave-marker arrêté (PID $grave_pid)."
    fi
    rm -f "$GRAVE_PID_FILE"
fi

# --- Sauvegarde du monde avant arrêt (décommenter si souhaité) ---------------
#
# echo "💾 [pre-down] Sauvegarde du monde en cours..."
# docker exec minecraft_server rcon-cli save-all
# sleep 3
# echo "✅ [pre-down] Sauvegarde terminée."
#
# ------------------------------------------------------------------------------

# --- Prévenir les joueurs avant arrêt (décommenter si souhaité) ---------------
#
# echo "📢 [pre-down] Notification aux joueurs..."
# docker exec minecraft_server rcon-cli "say Le serveur s'arrête dans 10 secondes !"
# sleep 10
#
# ------------------------------------------------------------------------------

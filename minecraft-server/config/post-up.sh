#!/usr/bin/env bash
# =============================================================================
# Hook : post-up.sh
# Exécuté APRÈS "docker compose up" par la commande "da up minecraft-server".
#
# Rôle : afficher les informations de connexion une fois le cluster démarré.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Charger les valeurs depuis .env pour afficher les bonnes infos.
if [ -f "$SCRIPT_DIR/.env" ]; then
    # Charger uniquement les variables non-commentées.
    set -a
    source <(grep -v '^\s*#' "$SCRIPT_DIR/.env" | grep -v '^\s*$')
    set +a
fi

# Valeurs par défaut si non définies dans .env.
SERVER_PORT="${SERVER_PORT:-25565}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-changeme-rcon}"
DYNMAP_PORT="${DYNMAP_PORT:-25566}"
TYPE="${TYPE:-FABRIC}"
VERSION="${VERSION:-LATEST}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🎮 Cluster Minecraft démarré"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🟢 Serveur Minecraft"
echo "     Adresse  : localhost:${SERVER_PORT}"
echo "     Type     : ${TYPE}"
echo "     Version  : ${VERSION}"
echo ""
echo "  🔧 RCON (administration)"
echo "     Adresse  : localhost:${RCON_PORT}"
echo "     Password : ${RCON_PASSWORD}"
echo ""
echo "  🗺️  Carte web Dynmap"
echo "     URL local : http://localhost:${DYNMAP_PORT}"
echo "     URL LAN   : http://<ip-de-l-hôte>:${DYNMAP_PORT}"
echo ""
echo "  💡 Commandes utiles"
echo "     CLI interactif      : docker exec -it minecraft_server rcon-cli"
echo "     Commande unique     : docker exec minecraft_server rcon-cli <cmd>"
echo "     Quitter les logs    : Ctrl+C"
echo ""
echo "  ⏳ Le premier démarrage peut prendre plusieurs minutes"
echo "     (téléchargement du serveur, des mods, génération du monde)."
echo "     Suivre la progression : da logs minecraft-server"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Watcher dynmap-auto-render ----------------------------------------------
# Comble les trous de rendu Dynmap autour des joueurs posés (compense l'absence
# du trigger 'chunkload' dans la version Fabric).
WATCHER_SCRIPT="$SCRIPT_DIR/dynmap-auto-render.sh"
WATCHER_PID_FILE="$SCRIPT_DIR/../shared/dynmap-auto-render.pid"
WATCHER_LOG_FILE="$SCRIPT_DIR/../shared/dynmap-auto-render.log"

# Tuer une instance précédente éventuelle (PID stale après crash hôte par ex.).
if [ -f "$WATCHER_PID_FILE" ]; then
    old_pid=$(cat "$WATCHER_PID_FILE" 2>/dev/null || true)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
    fi
    rm -f "$WATCHER_PID_FILE"
fi

if [ -x "$WATCHER_SCRIPT" ]; then
    nohup "$WATCHER_SCRIPT" >> "$WATCHER_LOG_FILE" 2>&1 &
    echo $! > "$WATCHER_PID_FILE"
    disown
    echo "🔁 [post-up] Watcher dynmap-auto-render démarré (PID $(cat "$WATCHER_PID_FILE"))."
    echo "   Logs : minecraft-server/shared/dynmap-auto-render.log"
    echo ""
fi

# --- Watcher dynmap-grave-marker ---------------------------------------------
# Synchronise les markers Dynmap du set "graves" depuis universal-graves.dat
# (le mod n'a pas d'intégration Dynmap native).
GRAVE_SCRIPT="$SCRIPT_DIR/dynmap-grave-marker.sh"
GRAVE_PID_FILE="$SCRIPT_DIR/../shared/dynmap-grave-marker.pid"
GRAVE_LOG_FILE="$SCRIPT_DIR/../shared/dynmap-grave-marker.log"

if [ -f "$GRAVE_PID_FILE" ]; then
    old_pid=$(cat "$GRAVE_PID_FILE" 2>/dev/null || true)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
    fi
    rm -f "$GRAVE_PID_FILE"
fi

if [ -x "$GRAVE_SCRIPT" ]; then
    nohup "$GRAVE_SCRIPT" >> "$GRAVE_LOG_FILE" 2>&1 &
    echo $! > "$GRAVE_PID_FILE"
    disown
    echo "🪦 [post-up] Watcher dynmap-grave-marker démarré (PID $(cat "$GRAVE_PID_FILE"))."
    echo "   Logs : minecraft-server/shared/dynmap-grave-marker.log"
    echo ""
fi

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
# .env.local (gitignored, optionnel) écrase les valeurs de .env — même contrat
# que docker-compose.yaml.
for env_file in "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.local"; do
    if [ -f "$env_file" ]; then
        set -a
        source <(grep -v '^\s*#' "$env_file" | grep -v '^\s*$')
        set +a
    fi
done

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

# --- Watcher dynmap-grave-marker (DÉSACTIVÉ en 1.20.1) -----------------------
# Le mod universal-graves 3.10.x (1.21.11) stockait son état dans
# world/data/universal-graves.dat — le watcher pollait ce fichier pour
# créer/supprimer les markers Dynmap des tombes + waystones-rich.
#
# En 1.20.1 (universal-graves ancien + waystones-fabric Balm), les NBT sont
# stockés ailleurs (probablement player NBT, format à découvrir). Le watcher
# tournait à vide et spammait "graves.dat absent". Désactivé jusqu'à ce qu'on
# adapte le parser au layout 1.20.1.
#
# Pour les waystones, l'intégration Dynmap native du mod
# (waystones-common.toml [compatibility] dynmap = true) crée automatiquement
# les markers waystones:waystones et waystones:sharestones — pas besoin de
# wrapper.
#
# Pour réactiver : décommenter le bloc ci-dessous + adapter
# config/dynmap-grave-marker.sh aux chemins NBT 1.20.1.
#
# GRAVE_SCRIPT="$SCRIPT_DIR/dynmap-grave-marker.sh"
# GRAVE_PID_FILE="$SCRIPT_DIR/../shared/dynmap-grave-marker.pid"
# GRAVE_LOG_FILE="$SCRIPT_DIR/../shared/dynmap-grave-marker.log"
#
# if [ -f "$GRAVE_PID_FILE" ]; then
#     old_pid=$(cat "$GRAVE_PID_FILE" 2>/dev/null || true)
#     if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
#         kill "$old_pid" 2>/dev/null || true
#     fi
#     rm -f "$GRAVE_PID_FILE"
# fi
#
# if [ -x "$GRAVE_SCRIPT" ]; then
#     nohup "$GRAVE_SCRIPT" >> "$GRAVE_LOG_FILE" 2>&1 &
#     echo $! > "$GRAVE_PID_FILE"
#     disown
#     echo "🪦 [post-up] Watcher dynmap-grave-marker démarré (PID $(cat "$GRAVE_PID_FILE"))."
#     echo "   Logs : minecraft-server/shared/dynmap-grave-marker.log"
#     echo ""
# fi

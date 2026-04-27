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
echo "  💡 Commandes utiles"
echo "     Console interactive : docker attach minecraft_server"
echo "     Commande RCON       : docker exec minecraft_server rcon-cli <cmd>"
echo "     Détacher la console : Ctrl+P puis Ctrl+Q"
echo ""
echo "  ⏳ Le premier démarrage peut prendre plusieurs minutes"
echo "     (téléchargement du serveur, des mods, génération du monde)."
echo "     Suivre la progression : da logs minecraft-server"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

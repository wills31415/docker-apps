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

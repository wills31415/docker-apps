#!/usr/bin/env bash
# =============================================================================
# Hook : pre-up.sh
# Exécuté AVANT "docker compose up" par la commande "da up minecraft-server".
#
# Rôle : préparer les répertoires nécessaires dans shared/ avant le démarrage.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"

echo "🔧 [pre-up] Préparation des répertoires..."

# Répertoire principal des données du serveur Minecraft.
# Contient le monde, les mods, les configs, les logs, etc.
mkdir -p "$SHARED_DIR/data"

# Répertoire pour les sauvegardes manuelles (utilisable par pre-down.sh).
mkdir -p "$SHARED_DIR/backups"

# -----------------------------------------------------------------------------
# Garde-fou : le container itzg tourne en uid=1000 gid=1000. Si des fichiers
# de shared/data/ appartiennent à un autre owner (typiquement root, suite à
# un `docker run` lancé sans `-u 1000:1000`), le serveur Minecraft échoue
# silencieusement (level.dat illisible → "World files may be corrupted").
# On détecte la dérive ici plutôt que de débugger 30 min de crash loop.
# -----------------------------------------------------------------------------
EXPECTED_UID=1000
EXPECTED_GID=1000
DRIFT_COUNT=$(find "$SHARED_DIR/data" \( ! -uid "$EXPECTED_UID" -o ! -gid "$EXPECTED_GID" \) 2>/dev/null | wc -l)
if [ "$DRIFT_COUNT" -gt 0 ]; then
    echo "❌ [pre-up] $DRIFT_COUNT fichier(s) dans shared/data/ n'appartiennent pas à ${EXPECTED_UID}:${EXPECTED_GID}."
    echo "   Le container Minecraft (uid=1000) ne pourra pas les lire/écrire → boot va échouer."
    echo "   Échantillon :"
    find "$SHARED_DIR/data" \( ! -uid "$EXPECTED_UID" -o ! -gid "$EXPECTED_GID" \) 2>/dev/null | head -5 | sed 's|^|     - |'
    echo "   Fix : sudo chown -R ${EXPECTED_UID}:${EXPECTED_GID} \"$SHARED_DIR/data\""
    exit 1
fi

echo "✅ [pre-up] Répertoires prêts."

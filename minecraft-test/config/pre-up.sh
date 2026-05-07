#!/usr/bin/env bash
# =============================================================================
# Hook pre-up : prépare shared/data/ et copie le .mrpack depuis le cluster prod
# (minecraft-server). Le test partage TOUJOURS le pack courant de prod — pour
# tester un pack différent, modifier MODRINTH_MODPACK dans .env (ex. URL custom).
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"
PROD_MRPACK="$SCRIPT_DIR/../../minecraft-server/shared/data/coupaing-craft-initial.mrpack"
TEST_MRPACK="$SHARED_DIR/data/coupaing-craft-initial.mrpack"

echo "🔧 [pre-up test] Préparation des répertoires..."
mkdir -p "$SHARED_DIR/data"
mkdir -p "$SHARED_DIR/backups"

# Copie du mrpack depuis prod si plus récent (idempotent)
if [ -f "$PROD_MRPACK" ]; then
    if [ ! -f "$TEST_MRPACK" ] || [ "$PROD_MRPACK" -nt "$TEST_MRPACK" ]; then
        cp "$PROD_MRPACK" "$TEST_MRPACK"
        echo "📦 [pre-up test] .mrpack copié depuis prod ($(du -h "$TEST_MRPACK" | cut -f1))"
    fi
else
    echo "⚠️  [pre-up test] Pack prod introuvable : $PROD_MRPACK"
    echo "   Démarrer le cluster prod au moins une fois pour le générer, ou poser un .mrpack manuellement."
    exit 1
fi

# Garde-fou perms (uid=1000 attendu par itzg)
EXPECTED_UID=1000
EXPECTED_GID=1000
DRIFT_COUNT=$(find "$SHARED_DIR/data" \( ! -uid "$EXPECTED_UID" -o ! -gid "$EXPECTED_GID" \) 2>/dev/null | wc -l)
if [ "$DRIFT_COUNT" -gt 0 ]; then
    echo "❌ [pre-up test] $DRIFT_COUNT fichier(s) shared/data/ pas en ${EXPECTED_UID}:${EXPECTED_GID}."
    echo "   Fix : sudo chown -R ${EXPECTED_UID}:${EXPECTED_GID} \"$SHARED_DIR/data\""
    exit 1
fi

echo "✅ [pre-up test] Prêt."

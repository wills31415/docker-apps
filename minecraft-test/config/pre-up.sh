#!/usr/bin/env bash
# =============================================================================
# Hook pre-up : prépare shared/data/ et copie le .mrpack depuis le cluster prod
# (minecraft-server). Le test partage TOUJOURS le pack courant de prod — pour
# tester un pack différent, modifier MODRINTH_MODPACK dans .env (ex. URL custom).
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"
SRC_TEST_MRPACK="$SCRIPT_DIR/../../minecraft-server/shared/data/coupaing-craft-test.mrpack"
SRC_PROD_MRPACK="$SCRIPT_DIR/../../minecraft-server/shared/data/coupaing-craft-initial.mrpack"
DST_MRPACK="$SHARED_DIR/data/coupaing-craft-test.mrpack"

echo "🔧 [pre-up test] Préparation des répertoires..."
mkdir -p "$SHARED_DIR/data"
mkdir -p "$SHARED_DIR/backups"

# Copie du test pack depuis prod (priorité au test pack généré par sync-pack.sh --test ;
# fallback sur le pack prod tel quel si pas de test pack — utile si tu veux juste un
# bac à sable Creative avec le pack actuel sans extras).
SRC=""
if [ -f "$SRC_TEST_MRPACK" ]; then
    SRC="$SRC_TEST_MRPACK"
    SRC_LABEL="test pack (mods + mods-test-only)"
elif [ -f "$SRC_PROD_MRPACK" ]; then
    SRC="$SRC_PROD_MRPACK"
    SRC_LABEL="pack prod (pas de test pack généré pour l'instant)"
fi

if [ -n "$SRC" ]; then
    if [ ! -f "$DST_MRPACK" ] || [ "$SRC" -nt "$DST_MRPACK" ]; then
        cp "$SRC" "$DST_MRPACK"
        echo "📦 [pre-up test] .mrpack copié depuis $SRC_LABEL ($(du -h "$DST_MRPACK" | cut -f1))"
    fi
else
    echo "⚠️  [pre-up test] Aucun .mrpack source trouvé."
    echo "   Lancer prod au moins une fois (./sync-pack.sh) ou bien :"
    echo "   ./sync-pack.sh --test pour générer un test pack."
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

#!/usr/bin/env bash
# =============================================================================
# Hook : pre-down.sh
# Exécuté AVANT "docker compose down" par la commande "da down postgresql".
#
# Rôle : émettre un avertissement avant l'arrêt du cluster.
# Ce hook est l'endroit idéal pour ajouter une logique de sauvegarde
# (pg_dump, notification d'un service dépendant, etc.).
# =============================================================================

set -e

echo "⚠️  [pre-down] Arrêt du cluster PostgreSQL en cours..."

# --- Exemple : dump automatique avant arrêt (décommentez si souhaité) --------
#
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# BACKUP_DIR="$SCRIPT_DIR/../shared/backups"
# TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
#
# mkdir -p "$BACKUP_DIR"
# echo "💾 [pre-down] Sauvegarde en cours → $BACKUP_DIR/dump_$TIMESTAMP.sql"
#
# docker exec postgresql_db pg_dump \
#     -U app_user \
#     -d app_db \
#     > "$BACKUP_DIR/dump_$TIMESTAMP.sql"
#
# echo "✅ [pre-down] Sauvegarde terminée."
# -----------------------------------------------------------------------------

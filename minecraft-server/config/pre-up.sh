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

echo "✅ [pre-up] Répertoires prêts."

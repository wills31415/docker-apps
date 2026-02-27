#!/usr/bin/env bash
# =============================================================================
# Hook : pre-up.sh
# Exécuté AVANT "docker compose up" par la commande "da up postgresql".
#
# Rôle : préparer les répertoires nécessaires dans shared/ et vérifier
# les prérequis avant le démarrage du cluster.
# =============================================================================

# Arrêter le script à la première erreur (bonne pratique dans les hooks).
set -e

# Répertoire config/ (là où ce script se trouve)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Répertoire shared/ du cluster
SHARED_DIR="$SCRIPT_DIR/../shared"

echo "🔧 [pre-up] Vérification des répertoires..."

# Créer les répertoires de données s'ils n'existent pas encore.
# Le répertoire "data/" doit exister avant le montage, sinon Docker
# le crée avec les droits root ce qui peut poser problème à PostgreSQL.
mkdir -p "$SHARED_DIR/data"

# Répertoire pour les scripts d'initialisation SQL (exécutés au 1er démarrage).
mkdir -p "$SHARED_DIR/initdb"

echo "✅ [pre-up] Répertoires prêts."

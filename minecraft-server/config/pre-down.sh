#!/usr/bin/env bash
# =============================================================================
# Hook : pre-down.sh
# Exécuté AVANT "docker compose down" par la commande "da down minecraft-server".
#
# Rôle : sauvegarder le monde et prévenir les joueurs avant l'arrêt.
# =============================================================================

set -e

echo "⚠️  [pre-down] Arrêt du serveur Minecraft en cours..."

# --- Sauvegarde du monde avant arrêt (décommenter si souhaité) ---------------
#
# echo "💾 [pre-down] Sauvegarde du monde en cours..."
# docker exec minecraft_server rcon-cli save-all
# sleep 3
# echo "✅ [pre-down] Sauvegarde terminée."
#
# ------------------------------------------------------------------------------

# --- Prévenir les joueurs avant arrêt (décommenter si souhaité) ---------------
#
# echo "📢 [pre-down] Notification aux joueurs..."
# docker exec minecraft_server rcon-cli "say Le serveur s'arrête dans 10 secondes !"
# sleep 10
#
# ------------------------------------------------------------------------------

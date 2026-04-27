#!/usr/bin/env bash
# ============================================================
#  post-down.sh — Message après arrêt du cluster
# ============================================================
set -euo pipefail
echo ""
echo "💤  Cluster ssh-lab arrêté proprement."
echo ""
echo "    Volumes nommés conservés (données persistées) :"
echo "      docker volume ls -f name=sshlab_"
echo ""
echo "    La clé admin est conservée dans shared/admin-key/"
echo "    Elle sera réutilisée au prochain démarrage."
echo ""
echo "    Pour redémarrer : da up ssh-lab"
echo "    Pour tout effacer (volumes inclus) :"
echo "      da down ssh-lab --volumes"
echo "      docker volume rm \$(docker volume ls -q -f name=sshlab_)"
echo ""

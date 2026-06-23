#!/usr/bin/env bash
# ============================================================
#  post-down.sh — Message après arrêt du cluster
# ============================================================
set -euo pipefail
echo ""
echo "💤  net-lab arrêté."
echo ""
echo "    Volumes nommés conservés :  docker volume ls -f name=netlab_"
echo "    Pour redémarrer        :  da up net-lab"
echo "    Pour tout effacer      :  ./volumes-rm.sh"
echo ""

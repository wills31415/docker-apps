#!/usr/bin/env bash
# ============================================================
#  box-status.sh — Vue lecture seule de la box (« ouvrir l'IHM »).
#  Affiche IP publique, baux, DMZ, redirections et les règles
#  iptables réellement actives dans le routeur.
# ============================================================
set -euo pipefail
BOX="net-lab-box"

if [ "$(docker inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null)" != "true" ]; then
    echo "❌  La box ($BOX) n'est pas démarrée. Lance : da up net-lab"
    exit 1
fi

exec docker exec "$BOX" box status

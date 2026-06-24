#!/usr/bin/env bash
# ============================================================
#  box-status.sh — Vue lecture seule de la box (« ouvrir l'IHM »).
#
#  Usage :
#    ./box-status.sh               état courant (config + règles + compteurs)
#    ./box-status.sh conntrack     table de suivi de connexions (NAT en direct)
#    ./box-status.sh --watch [..]  rafraîchit toutes les 2 s (Ctrl+C pour sortir)
#
#  Affiche l'IP publique, les baux, la DMZ, les redirections, le mode
#  d'egress et les règles iptables réellement actives dans le routeur.
# ============================================================
set -euo pipefail
BOX="net-lab-box"

WATCH=0
SUB="status"
for a in "$@"; do
    case "$a" in
        --watch|-w)        WATCH=1 ;;
        status|conntrack)  SUB="$a" ;;
        -h|--help)         grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0 ;;
        *) echo "❌  argument inconnu : $a"; echo "   usage : $(basename "$0") [--watch] [status|conntrack]"; exit 1 ;;
    esac
done

if [ "$(docker inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null)" != "true" ]; then
    echo "❌  La box ($BOX) n'est pas démarrée. Lance : da up net-lab"
    exit 1
fi

if [ "$WATCH" -eq 1 ]; then
    trap 'echo; exit 0' INT
    while true; do
        clear
        echo "🔄  box-status --watch ($SUB) — Ctrl+C pour quitter — $(date +%H:%M:%S)"
        docker exec "$BOX" box "$SUB"
        sleep 2
    done
fi

exec docker exec "$BOX" box "$SUB"

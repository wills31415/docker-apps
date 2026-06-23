#!/usr/bin/env bash
# ============================================================
#  post-up.sh — Résumé affiché après un démarrage réussi
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=topology.conf
source "$SCRIPT_DIR/topology.conf"
# shellcheck source=box.conf
source "$SCRIPT_DIR/box.conf"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              net-lab — homelab simulé démarré ✅              ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  IP publique (box) : %-42s║\n" "$PUBLIC_IP"
printf "║  LAN %-14s  DMZ %-14s  WAN %-12s║\n" "$LAN_SUBNET" "$DMZ_SUBNET" "$WAN_SUBNET"
printf "║  servers : %-3d   clients : %-3d   (nas=1, gateway=1)          ║\n" \
    "$N_SERVERS" "$N_CLIENTS"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Auth : root / ROOT_PASSWORD sur chaque machine (pas la box)  ║"
echo "║  Test depuis un client (acteur 'extérieur') :                ║"
printf "║    docker exec -it net-lab-client-1 bash                      ║\n"
printf "║    ssh -p 2222 root@%-15s   # → gateway (jump)      ║\n" "$PUBLIC_IP"
printf "║    ssh -p 2022 root@%-15s   # → NAS (DMZ)           ║\n" "$PUBLIC_IP"
printf "║    curl http://%-15s:8080      # → HTTP démo NAS     ║\n" "$PUBLIC_IP"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Box (« IHM ») — édite config/box.conf puis :                ║"
echo "║    ./box-apply.sh     applique à chaud (DMZ + redirections)   ║"
echo "║    ./box-status.sh    affiche l'état courant du routeur       ║"
echo "║  Machines : ./cluster-exec.sh <groupe> \"<cmd>\"  (hors box)    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

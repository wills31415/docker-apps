#!/usr/bin/env bash
# ============================================================
#  Entrypoint — BOX
#  Active le routage IP puis applique la config (box apply),
#  enfin reste en vie pour servir l'« IHM » (box-apply.sh).
# ============================================================
set -euo pipefail

# Routage entre les interfaces (WAN / LAN / DMZ)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

echo ""
echo "┌──────────────────────────────────────────────────┐"
echo "│  📡  BOX démarrée — routeur NAT / pare-feu        │"
printf "│  IP publique : %-33s │\n" "${PUBLIC_IP:-?}"
echo "│  Réseaux : wan + lan + dmz                        │"
echo "│  Config : /etc/net-lab/box.conf  (l'« IHM »)      │"
echo "└──────────────────────────────────────────────────┘"
echo ""

# Application initiale des règles depuis box.conf
box apply || echo "⚠️  box apply a échoué au démarrage"

# La box ne fait pas tourner sshd : on n'y touche que via box-apply.sh
exec sleep infinity

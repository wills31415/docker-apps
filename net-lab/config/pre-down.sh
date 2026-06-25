#!/usr/bin/env bash
# ============================================================
#  pre-down.sh — Message avant l'arrêt du cluster
# ============================================================
set -euo pipefail
echo ""
echo "🛑  Arrêt de net-lab…"
echo "    ⚠  Conteneurs détruits ⇒ writable layer des nodes perdu (users,"
echo "       paquets installés à chaud, tweaks /etc, etc.)."
echo "       Pour un vrai reboot préservant l'état : ./reboot.sh"
echo "    Bind-mounts hôte (shared/) : conservés."
echo ""

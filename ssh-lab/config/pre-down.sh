#!/usr/bin/env bash
# ============================================================
#  pre-down.sh — Message avant l'arrêt du cluster
# ============================================================
set -euo pipefail
echo ""
echo "🛑  Arrêt du cluster ssh-lab…"
echo "    Volumes nommés (données /root, /etc/ssh) : conservés"
echo "    shared/admin-key/  : clé admin conservée"
echo "    shared/uploads/    : uploads conservés"
echo ""

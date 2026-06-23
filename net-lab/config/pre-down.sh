#!/usr/bin/env bash
# ============================================================
#  pre-down.sh — Message avant l'arrêt du cluster
# ============================================================
set -euo pipefail
echo ""
echo "🛑  Arrêt de net-lab…"
echo "    Volumes nommés (/root, /etc/ssh des machines) : conservés"
echo "    shared/uploads/ et shared/box/ : conservés"
echo ""

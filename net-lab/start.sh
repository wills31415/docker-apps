#!/usr/bin/env bash
# ============================================================
#  start.sh — Relance les conteneurs préalablement stoppés
#             (writable layer préservé). Pendant de ./stop.sh.
#
#  ⚠️  Temporaire : à supprimer quand `da start net-lab` existe.
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/config"
docker compose start "$@"

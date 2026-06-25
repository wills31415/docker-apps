#!/usr/bin/env bash
# ============================================================
#  stop.sh — Arrête les conteneurs SANS les détruire (writable
#            layer préservé). Soft cycle, type "power off" sur
#            une vraie machine.
#
#  Combiner avec ./start.sh pour un reboot fidèle (./reboot.sh).
#
#  ⚠️  Temporaire : à supprimer quand `da stop net-lab` existe.
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/config"
docker compose stop "$@"

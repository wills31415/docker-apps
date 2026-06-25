#!/usr/bin/env bash
# ============================================================
#  reboot.sh — Soft reboot = stop + start. Le writable layer de
#              chaque conteneur est intégralement préservé : c'est
#              équivalent à un power cycle sur une vraie machine.
#
#  Contraste avec `da restart net-lab` qui fait down + up =
#  conteneurs recréés = état des nodes wipé (= fresh install).
#
#  ⚠️  Temporaire : à supprimer quand `da start/stop net-lab` existent.
# ============================================================
set -euo pipefail
DIR="$(dirname "${BASH_SOURCE[0]}")"
"$DIR/stop.sh" "$@" && "$DIR/start.sh" "$@"

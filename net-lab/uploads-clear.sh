#!/usr/bin/env bash
# ============================================================
#  uploads-clear.sh — Vide un (ou tous) les sous-répertoires
#                     de shared/uploads/.
#  Usage :
#    ./uploads-clear.sh <groupe>
#  Groupes :
#    all       → vide TOUS les sous-répertoires
#    all-dir   → vide seulement shared/uploads/all/
#    gateway | servers | clients | nas → ce groupe uniquement
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP="$SCRIPT_DIR/shared/uploads"
usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage
[ $# -lt 1 ] && { echo "❌  Usage : $(basename "$0") <groupe>"; exit 1; }

clear_dir() {
    local d="$UP/$1"
    if [ -d "$d" ]; then
        find "$d" -mindepth 1 -delete
        echo "🧹  vidé : shared/uploads/$1/"
    else
        echo "·   absent : shared/uploads/$1/"
    fi
}

case "$1" in
    all)      for g in all gateway servers clients nas; do clear_dir "$g"; done ;;
    all-dir)  clear_dir all ;;
    gateway|servers|clients|nas) clear_dir "$1" ;;
    *) echo "❌  Groupe invalide : '$1' (all|all-dir|gateway|servers|clients|nas)"; exit 1 ;;
esac

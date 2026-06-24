#!/usr/bin/env bash
# ============================================================
#  upload.sh — Dépose un fichier dans le volume partagé d'un
#              groupe de machines (bind-mount /uploads, ro).
#
#  Usage :
#    ./upload.sh <groupe> <fichier>
#
#  Groupes :
#    all       → /uploads/all/  dans TOUTES les machines
#    gateway   → /uploads/role/ dans la gateway
#    servers   → /uploads/role/ dans les servers
#    clients   → /uploads/role/ dans les clients
#    nas       → /uploads/role/ dans le NAS
#
#  (La box n'a pas de volume d'upload : elle ne se touche
#   qu'via box-apply.sh / box-status.sh.)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage

if [ $# -lt 2 ]; then
    echo "❌  Usage : $(basename "$0") <groupe> <fichier>"
    exit 1
fi
TARGET="$1"; FILE="$2"

case "$TARGET" in
    all|gateway|servers|clients|nas) ;;
    box) echo "❌  La box n'accepte pas d'upload (config via box-apply.sh)."; exit 1 ;;
    *)   echo "❌  Groupe invalide : '$TARGET' (all|gateway|servers|clients|nas)"; exit 1 ;;
esac
[ -f "$FILE" ] || { echo "❌  Fichier introuvable : $FILE"; exit 1; }

DEST="$SCRIPT_DIR/shared/uploads/$TARGET"
mkdir -p "$DEST"
BASENAME="$(basename "$FILE")"
cp "$FILE" "$DEST/$BASENAME"

if [ "$TARGET" = "all" ]; then CPATH="/uploads/all/$BASENAME"; else CPATH="/uploads/role/$BASENAME"; fi
echo ""
echo "✅  Upload : $BASENAME → shared/uploads/$TARGET/"
echo "   Dans la machine : $CPATH"
echo "   Ex : ./cluster-exec.sh $TARGET \"ls -l $CPATH\""
echo ""

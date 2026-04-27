#!/usr/bin/env bash
# ============================================================
#  upload.sh — Dépose un fichier dans le volume partagé du
#              cluster ssh-lab (bind-mount, instantané).
#
#  Usage :
#    ./upload.sh <groupe> <fichier>
#
#  Groupes disponibles :
#    all       → /uploads/all/  dans TOUS les conteneurs
#    master    → /uploads/role/ dans le MASTER uniquement
#    clients   → /uploads/role/ dans les CLIENTs
#    gateways  → /uploads/role/ dans les GATEWAYs
#    servers   → /uploads/role/ dans les SERVERs
#
#  Exemples :
#    ./upload.sh all     deploy.tar.gz
#    ./upload.sh servers app-config.tar.gz
#    ./upload.sh master  admin-scripts.tar.gz
#    ./upload.sh clients client-setup.sh
#    ./upload.sh gateways gw-rules.sh
#
#  Note : les volumes sont montés en lecture seule (ro).
#  Pour modifier/extraire, copier vers /tmp/ ou /root/
#  (volume nommé persisté) dans le conteneur.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; fi

if [ $# -lt 2 ]; then
    echo "❌  Arguments manquants."
    echo "   Usage : $(basename "$0") <groupe> <fichier>"
    echo "   Aide  : $(basename "$0") --help"
    exit 1
fi

TARGET="$1"
FILE="$2"

# ── Validation du groupe ──────────────────────────────────────
case "$TARGET" in
    all|master|clients|gateways|servers) ;;
    *)
        echo "❌  Groupe invalide : '$TARGET'"
        echo "   Valeurs acceptées : all | master | clients | gateways | servers"
        exit 1 ;;
esac

# ── Validation du fichier ─────────────────────────────────────
if [ ! -f "$FILE" ]; then
    echo "❌  Fichier introuvable : $FILE"
    exit 1
fi

# ── Copie ─────────────────────────────────────────────────────
DEST_DIR="$SCRIPT_DIR/shared/uploads/$TARGET"
mkdir -p "$DEST_DIR"
BASENAME="$(basename "$FILE")"
cp "$FILE" "$DEST_DIR/$BASENAME"

# Chemin dans le conteneur
if [ "$TARGET" = "all" ]; then
    CPATH="/uploads/all/$BASENAME"
else
    CPATH="/uploads/role/$BASENAME"
fi

# ── Résumé ────────────────────────────────────────────────────
echo ""
echo "✅  Upload réussi"
echo "   Groupe  : $TARGET"
echo "   Fichier : $BASENAME → shared/uploads/$TARGET/"
echo "   Dispo   : $CPATH"
echo ""
echo "💡  Depuis un conteneur :"
if [[ "$BASENAME" == *.tar.gz ]] || [[ "$BASENAME" == *.tgz ]]; then
    echo "   # Lister l'archive"
    echo "   docker exec <conteneur> tar tzf ${CPATH}"
    echo ""
    echo "   # Extraire dans /tmp/ (temporaire)"
    echo "   docker exec <conteneur> tar xzf ${CPATH} -C /tmp/"
    echo ""
    echo "   # Extraire dans /root/ (persisté dans le volume nommé)"
    echo "   docker exec <conteneur> tar xzf ${CPATH} -C /root/"
elif [[ "$BASENAME" == *.sh ]]; then
    echo "   docker exec -it <conteneur> bash ${CPATH}"
else
    echo "   docker exec <conteneur> ls -lh ${CPATH}"
fi
echo ""

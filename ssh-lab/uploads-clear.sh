#!/usr/bin/env bash
# ============================================================
#  uploads-clear.sh — Vide un ou tous les sous-répertoires
#                     de shared/uploads/.
#
#  Usage :
#    ./uploads-clear.sh <groupe>
#
#  Groupes disponibles :
#    all       → vide ALL les sous-répertoires (all, master,
#                clients, gateways, servers)
#    all-dir   → vide uniquement shared/uploads/all/
#    master    → vide shared/uploads/master/
#    clients   → vide shared/uploads/clients/
#    gateways  → vide shared/uploads/gateways/
#    servers   → vide shared/uploads/servers/
#
#  Note : les sous-répertoires eux-mêmes sont conservés.
#  Seuls les fichiers qu'ils contiennent sont supprimés.
#  Les fichiers .gitkeep sont toujours préservés.
#
#  Exemples :
#    ./uploads-clear.sh all        # tout vider
#    ./uploads-clear.sh servers    # vider uniquement servers/
#    ./uploads-clear.sh master     # vider uniquement master/
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOADS_BASE="$SCRIPT_DIR/shared/uploads"

usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage

if [ $# -lt 1 ]; then
    echo "❌  Argument manquant."
    echo "   Usage : $(basename "$0") <groupe>"
    echo "   Aide  : $(basename "$0") --help"
    exit 1
fi

GROUP="$1"

# ── Construction de la liste des répertoires à vider ─────────
DIRS=()
case "$GROUP" in
    all)
        DIRS+=(
            "$UPLOADS_BASE/all"
            "$UPLOADS_BASE/master"
            "$UPLOADS_BASE/clients"
            "$UPLOADS_BASE/gateways"
            "$UPLOADS_BASE/servers"
        )
        ;;
    # "all-dir" pour cibler uniquement le répertoire all/ sans ambiguïté
    all-dir)    DIRS+=("$UPLOADS_BASE/all")     ;;
    master)     DIRS+=("$UPLOADS_BASE/master")  ;;
    clients)    DIRS+=("$UPLOADS_BASE/clients") ;;
    gateways)   DIRS+=("$UPLOADS_BASE/gateways") ;;
    servers)    DIRS+=("$UPLOADS_BASE/servers") ;;
    *)
        echo "❌  Groupe invalide : '$GROUP'"
        echo "   Valeurs acceptées : all | all-dir | master | clients | gateways | servers"
        exit 1
        ;;
esac

# ── Vidage ────────────────────────────────────────────────────
echo ""
CLEARED=0
ALREADY_EMPTY=0

for dir in "${DIRS[@]}"; do
    rel="shared/uploads/$(basename "$dir")/"

    if [ ! -d "$dir" ]; then
        echo "  ⚠️   $rel — répertoire introuvable, ignoré"
        continue
    fi

    # Compter les fichiers non-.gitkeep
    FILE_COUNT=$(find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' | wc -l)

    if [ "$FILE_COUNT" -eq 0 ]; then
        echo "  ℹ️   $rel — déjà vide"
        ALREADY_EMPTY=$(( ALREADY_EMPTY + 1 ))
        continue
    fi

    # Lister les fichiers avant suppression
    echo "  🗑️   $rel — suppression de $FILE_COUNT fichier(s) :"
    find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' \
        | sort \
        | while IFS= read -r f; do
            printf "        - %s\n" "$(basename "$f")"
        done

    # Supprimer tous les fichiers sauf .gitkeep
    find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' -delete

    CLEARED=$(( CLEARED + 1 ))
done

# ── Résumé ────────────────────────────────────────────────────
TOTAL="${#DIRS[@]}"
echo ""

if [ "$CLEARED" -eq 0 ] && [ "$ALREADY_EMPTY" -eq "$TOTAL" ]; then
    echo "  ℹ️   Tous les répertoires étaient déjà vides — rien à faire."
elif [ "$CLEARED" -gt 0 ]; then
    printf "  ✅  %d/%d répertoire(s) vidé(s)\n" "$CLEARED" "$TOTAL"
    [ "$ALREADY_EMPTY" -gt 0 ] && \
        printf "  ℹ️   %d/%d étai(en)t déjà vide(s)\n" "$ALREADY_EMPTY" "$TOTAL"
fi
echo ""

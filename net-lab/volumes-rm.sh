#!/usr/bin/env bash
# ============================================================
#  volumes-rm.sh — Supprime les volumes nommés de net-lab
#                  (préfixe netlab_) pour repartir de zéro.
#  Le cluster doit être arrêté (da down net-lab).
#  Usage :
#    ./volumes-rm.sh [-y]      (-y : sans confirmation)
# ============================================================
set -euo pipefail

ASSUME_YES=0
[ "${1:-}" = "-y" ] && ASSUME_YES=1

mapfile -t VOLS < <(docker volume ls -q -f name=netlab_ 2>/dev/null || true)

if [ "${#VOLS[@]}" -eq 0 ]; then
    echo "✓  Aucun volume netlab_ à supprimer."
    exit 0
fi

echo "Volumes netlab_ trouvés (${#VOLS[@]}) :"
printf '   %s\n' "${VOLS[@]}"
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Supprimer DÉFINITIVEMENT ces volumes ? [y/N] " ans
    case "$ans" in y|Y|yes|oui) ;; *) echo "Annulé."; exit 0 ;; esac
fi

# Échoue proprement si un volume est encore utilisé (cluster up).
if docker volume rm "${VOLS[@]}"; then
    echo "🗑️   ${#VOLS[@]} volume(s) supprimé(s)."
else
    echo "❌  Échec — le cluster est-il bien arrêté ? (da down net-lab)"
    exit 1
fi

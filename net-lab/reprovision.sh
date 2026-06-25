#!/usr/bin/env bash
# ============================================================
#  reprovision.sh — Pousse la conf admin courante (topology.conf)
#                   sur des conteneurs vivants, sans recreate.
#
#  Mécanisme :
#    1. Régénère shared/node/runtime.conf depuis topology.conf
#       (ROOT_PASSWORD, LOG_LEVEL). Ce fichier est bind-monté ro
#       dans chaque node à /net-lab/runtime.conf.
#    2. Pour chaque node ciblé : supprime le marker
#       /var/lib/net-lab/.provisioned puis docker restart.
#       L'entrypoint détecte l'absence du marker, ré-exécute la
#       phase 1, qui source le runtime.conf à jour ⇒ vraie
#       propagation.
#
#  Le writable layer du conteneur est préservé (pas de recreate) ⇒
#  l'état admin (users, paquets, dirs créés) survit.
#
#  ⚠️  La BOX est exclue (elle s'administre via ./box-apply.sh).
#
#  Usage :
#    ./reprovision.sh <groupe|machine>
#
#  Groupes : all | gateway | servers | clients | nas
#  Machines : gateway | server-N | client-N | nas
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/config/topology.conf"
RUNTIME="$SCRIPT_DIR/shared/node/runtime.conf"

usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage

if [ $# -ne 1 ]; then
    echo "❌  Usage : $(basename "$0") <groupe|machine>"
    exit 1
fi
GROUP="$1"

[ -f "$CONF" ] || { echo "❌  topology.conf introuvable : $CONF"; exit 1; }
# shellcheck source=config/topology.conf
source "$CONF"

# ── Validation des valeurs hot-tunables ───────────────────────
[ -n "${ROOT_PASSWORD:-}" ] || { echo "❌  ROOT_PASSWORD non défini dans topology.conf"; exit 1; }
VALID_LOG="QUIET FATAL ERROR INFO VERBOSE DEBUG DEBUG1 DEBUG2 DEBUG3"
echo "$VALID_LOG" | grep -qw "${LOG_LEVEL:-}" || { echo "❌  LOG_LEVEL invalide : '${LOG_LEVEL:-}'"; exit 1; }

# ── Régénération de shared/node/runtime.conf ──────────────────
mkdir -p "$(dirname "$RUNTIME")"
cat > "$RUNTIME" << RUNTIME_CONF
# AUTO-GÉNÉRÉ par reprovision.sh depuis topology.conf — NE PAS ÉDITER À LA MAIN.
ROOT_PASSWORD=${ROOT_PASSWORD}
LOG_LEVEL=${LOG_LEVEL}
RUNTIME_CONF
echo "📝  runtime.conf régénéré (LOG_LEVEL=${LOG_LEVEL})"

# ── Construction de la liste de conteneurs ────────────────────
CONTAINERS=()
case "$GROUP" in
    box|net-lab-box)
        echo "⛔  La box ne se re-provisionne pas (stateless, gérée via ./box-apply.sh)."
        exit 1 ;;
    all)
        CONTAINERS+=("net-lab-gateway")
        for i in $(seq 1 "${N_SERVERS:-0}"); do CONTAINERS+=("net-lab-server-$i"); done
        CONTAINERS+=("net-lab-nas")
        for i in $(seq 1 "${N_CLIENTS:-0}"); do CONTAINERS+=("net-lab-client-$i"); done ;;
    gateway)  CONTAINERS+=("net-lab-gateway") ;;
    nas)      CONTAINERS+=("net-lab-nas") ;;
    servers)  for i in $(seq 1 "${N_SERVERS:-0}"); do CONTAINERS+=("net-lab-server-$i"); done ;;
    clients)  for i in $(seq 1 "${N_CLIENTS:-0}"); do CONTAINERS+=("net-lab-client-$i"); done ;;
    server-[0-9]*|client-[0-9]*)
        CONTAINERS+=("net-lab-${GROUP}") ;;
    net-lab-*)
        CONTAINERS+=("$GROUP") ;;
    *)
        echo "❌  Groupe ou machine inconnu : '$GROUP'"
        echo "   Groupes : all | gateway | servers | clients | nas"
        echo "   Machines : gateway | server-N | client-N | nas"
        exit 1 ;;
esac

[ "${#CONTAINERS[@]}" -eq 0 ] && { echo "⚠️  Aucune machine dans '$GROUP'."; exit 1; }
docker info &>/dev/null || { echo "❌  Docker inaccessible."; exit 1; }

# ── Re-provisioning : rm marker + restart ─────────────────────
TOTAL="${#CONTAINERS[@]}"
echo ""
printf "♻️   reprovision [%s] → %d machine(s)\n\n" "$GROUP" "$TOTAL"

SUCCESS=0; FAIL=0
for c in "${CONTAINERS[@]}"; do
    if ! docker inspect "$c" &>/dev/null; then
        printf "── ⚫ %s  (absent)\n" "$c"
        FAIL=$((FAIL+1))
        continue
    fi
    if docker exec "$c" rm -f /var/lib/net-lab/.provisioned 2>/dev/null \
       && docker restart "$c" >/dev/null; then
        printf "── ✅ %s  (marker supprimé + restart)\n" "$c"
        SUCCESS=$((SUCCESS+1))
    else
        printf "── ❌ %s  (échec rm/restart)\n" "$c"
        FAIL=$((FAIL+1))
    fi
done
echo ""
printf "    ✅ %d/%d" "$SUCCESS" "$TOTAL"
[ "$FAIL" -gt 0 ] && printf "  │  ❌ %d échec(s)" "$FAIL"
printf "\n\n"
[ "$FAIL" -eq 0 ]

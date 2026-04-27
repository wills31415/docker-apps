#!/usr/bin/env bash
# ============================================================
#  cluster-exec.sh — Exécution d'une commande bash en parallèle
#                    sur un groupe de conteneurs via docker exec.
#
#  Usage :
#    ./cluster-exec.sh <groupe|nœud> <commande>
#
#  Groupes disponibles :
#    all       → master + tous les clients, gateways, servers
#    master    → master uniquement
#    clients   → tous les clients
#    gateways  → toutes les gateways
#    servers   → tous les servers
#    client-N  → un client précis    (ex: client-2)
#    gateway-N → une gateway précise (ex: gateway-1)
#    server-N  → un server précis    (ex: server-3)
#
#  Exemples :
#    ./cluster-exec.sh all     "hostname && uptime"
#    ./cluster-exec.sh servers "df -h /"
#    ./cluster-exec.sh master  "lab-exec servers 'hostname'"
#    ./cluster-exec.sh server-2 "cat /etc/os-release | grep NAME"
#    ./cluster-exec.sh gateways "ss -tlnp | grep :22"
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/config/cluster.conf"

usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; fi

if [ $# -lt 2 ]; then
    echo "❌  Arguments manquants."
    echo "   Usage : $(basename "$0") <groupe|nœud> <commande>"
    echo "   Aide  : $(basename "$0") --help"
    exit 1
fi

GROUP="$1"; shift
COMMAND="$*"

[ -z "$COMMAND" ] && { echo "❌  Commande vide."; exit 1; }

# ── Chargement de cluster.conf ───────────────────────────────
if [ ! -f "$CONF" ]; then
    echo "❌  cluster.conf introuvable : $CONF"
    exit 1
fi
# shellcheck source=config/cluster.conf
source "$CONF"

# ── Construction de la liste des conteneurs ───────────────────
CONTAINERS=()
case "$GROUP" in
    all)
        CONTAINERS+=("ssh-master")
        for i in $(seq 1 "$N_CLIENTS");  do CONTAINERS+=("ssh-client-$i");  done
        for i in $(seq 1 "$N_GATEWAYS"); do CONTAINERS+=("ssh-gateway-$i"); done
        for i in $(seq 1 "$N_SERVERS");  do CONTAINERS+=("ssh-server-$i");  done
        ;;
    master)                       CONTAINERS+=("ssh-master") ;;
    clients)   for i in $(seq 1 "$N_CLIENTS");  do CONTAINERS+=("ssh-client-$i");  done ;;
    gateways)  for i in $(seq 1 "$N_GATEWAYS"); do CONTAINERS+=("ssh-gateway-$i"); done ;;
    servers)   for i in $(seq 1 "$N_SERVERS");  do CONTAINERS+=("ssh-server-$i");  done ;;
    client-[0-9]*|gateway-[0-9]*|server-[0-9]*)
        CONTAINERS+=("ssh-${GROUP}") ;;
    ssh-client-[0-9]*|ssh-gateway-[0-9]*|ssh-server-[0-9]*|ssh-master)
        CONTAINERS+=("$GROUP") ;;
    *)
        echo "❌  Groupe ou nœud inconnu : '$GROUP'"
        echo "   Groupes : all | master | clients | gateways | servers"
        echo "   Nœuds   : client-N | gateway-N | server-N"
        exit 1 ;;
esac

[ "${#CONTAINERS[@]}" -eq 0 ] && {
    echo "⚠️  Aucun conteneur dans '$GROUP' — vérifiez cluster.conf"
    exit 1
}

docker info &>/dev/null || { echo "❌  Docker inaccessible."; exit 1; }

# ── Exécution en parallèle ────────────────────────────────────
TMPDIR_EXEC="$(mktemp -d /tmp/cluster-exec.XXXXXX)"
trap 'rm -rf "$TMPDIR_EXEC"' EXIT

TOTAL="${#CONTAINERS[@]}"
echo ""
printf "🔧  cluster-exec [%s] → %d conteneur(s)\n" "$GROUP" "$TOTAL"
printf "    Commande : %s\n" "$COMMAND"
printf "    %s\n" "$(printf '═%.0s' $(seq 1 62))"
echo ""

START_NS="$(date +%s%N 2>/dev/null || echo 0)"

declare -A BGPIDS
for cname in "${CONTAINERS[@]}"; do
    (
        docker exec "$cname" bash -c "$COMMAND" > "$TMPDIR_EXEC/${cname}.out" 2>&1
        echo $? > "$TMPDIR_EXEC/${cname}.exit"
    ) &
    BGPIDS["$cname"]=$!
done

for cname in "${CONTAINERS[@]}"; do
    wait "${BGPIDS[$cname]}" 2>/dev/null || true
done

END_NS="$(date +%s%N 2>/dev/null || echo 0)"
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))

# ── Affichage des résultats ───────────────────────────────────
SUCCESS=0; FAIL=0

for cname in "${CONTAINERS[@]}"; do
    outfile="$TMPDIR_EXEC/${cname}.out"
    exitfile="$TMPDIR_EXEC/${cname}.exit"
    exit_code=0; [ -f "$exitfile" ] && exit_code="$(cat "$exitfile")"

    SEP_LEN=$(( 55 - ${#cname} )); [ "$SEP_LEN" -lt 4 ] && SEP_LEN=4
    SEP="$(printf '─%.0s' $(seq 1 $SEP_LEN))"

    if [ "$exit_code" -eq 0 ]; then
        STATUS="✅"; SUCCESS=$(( SUCCESS + 1 ))
    else
        docker inspect "$cname" &>/dev/null 2>&1 \
            && STATUS="❌ (exit ${exit_code})" \
            || STATUS="⚫ (absent)"
        FAIL=$(( FAIL + 1 ))
    fi

    printf "── %s %s %s\n" "$STATUS" "$cname" "$SEP"
    if [ -f "$outfile" ] && [ -s "$outfile" ]; then sed 's/^/   /' "$outfile"
    else echo "   (pas de sortie)"; fi
    echo ""
done

printf "    %s\n" "$(printf '═%.0s' $(seq 1 62))"
printf "    ✅ %d/%d succès" "$SUCCESS" "$TOTAL"
[ "$FAIL" -gt 0 ] && printf "  │  ❌ %d échec(s)" "$FAIL"
[ "$ELAPSED_MS" -gt 0 ] && printf "  │  ⏱  %dms" "$ELAPSED_MS"
printf "\n\n"

[ "$FAIL" -eq 0 ]

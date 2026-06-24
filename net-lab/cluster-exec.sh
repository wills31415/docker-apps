#!/usr/bin/env bash
# ============================================================
#  cluster-exec.sh — Exécute une commande en parallèle sur un
#                    groupe de MACHINES via docker exec.
#
#  ⚠️  La BOX est exclue : on ne l'administre QUE via l'« IHM »
#      (./box-apply.sh et ./box-status.sh).
#
#  Usage :
#    ./cluster-exec.sh <groupe|machine> <commande>
#
#  Groupes :
#    all       → gateway + servers + nas + clients
#    gateway   → la gateway
#    servers   → tous les servers
#    clients   → tous les clients
#    nas       → le NAS
#  Machines : gateway | server-N | client-N | nas
#
#  Exemples :
#    ./cluster-exec.sh all      "hostname -I"
#    ./cluster-exec.sh servers  "ip route"
#    ./cluster-exec.sh nas      "ss -tlnp"
#    ./cluster-exec.sh client-1 "ssh -p 2222 root@\$PUBLIC_IP hostname"
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/config/topology.conf"

usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage

if [ $# -lt 2 ]; then
    echo "❌  Usage : $(basename "$0") <groupe|machine> <commande>"
    exit 1
fi
GROUP="$1"; shift
COMMAND="$*"
[ -z "$COMMAND" ] && { echo "❌  Commande vide."; exit 1; }

[ -f "$CONF" ] || { echo "❌  topology.conf introuvable : $CONF"; exit 1; }
# shellcheck source=config/topology.conf
source "$CONF"

# ── Construction de la liste de conteneurs ────────────────────
CONTAINERS=()
case "$GROUP" in
    box|net-lab-box)
        echo "⛔  La box ne s'administre PAS ici."
        echo "    Utilise ./box-apply.sh (config) et ./box-status.sh (état)."
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

# ── Exécution en parallèle ────────────────────────────────────
TMP="$(mktemp -d /tmp/net-lab-exec.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
TOTAL="${#CONTAINERS[@]}"
echo ""
printf "🔧  cluster-exec [%s] → %d machine(s)\n" "$GROUP" "$TOTAL"
printf "    Commande : %s\n" "$COMMAND"
printf "    %s\n\n" "$(printf '═%.0s' $(seq 1 62))"

declare -A PIDS
for c in "${CONTAINERS[@]}"; do
    ( docker exec "$c" bash -c "$COMMAND" >"$TMP/$c.out" 2>&1; echo $? >"$TMP/$c.exit" ) &
    PIDS["$c"]=$!
done
for c in "${CONTAINERS[@]}"; do wait "${PIDS[$c]}" 2>/dev/null || true; done

SUCCESS=0; FAIL=0
for c in "${CONTAINERS[@]}"; do
    ec=0; [ -f "$TMP/$c.exit" ] && ec="$(cat "$TMP/$c.exit")"
    if [ "$ec" -eq 0 ]; then STATUS="✅"; SUCCESS=$((SUCCESS+1))
    else
        docker inspect "$c" &>/dev/null && STATUS="❌ (exit $ec)" || STATUS="⚫ (absent)"
        FAIL=$((FAIL+1))
    fi
    printf "── %s %s\n" "$STATUS" "$c"
    if [ -s "$TMP/$c.out" ]; then sed 's/^/   /' "$TMP/$c.out"; else echo "   (pas de sortie)"; fi
    echo ""
done
printf "    %s\n" "$(printf '═%.0s' $(seq 1 62))"
printf "    ✅ %d/%d" "$SUCCESS" "$TOTAL"
[ "$FAIL" -gt 0 ] && printf "  │  ❌ %d échec(s)" "$FAIL"
printf "\n\n"
[ "$FAIL" -eq 0 ]

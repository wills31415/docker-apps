#!/usr/bin/env bash
# ============================================================
#  volumes-rm.sh — Supprime les volumes Docker nommés (sshlab_)
#                  associés à un groupe de conteneurs.
#
#  ⚠️  Le cluster DOIT être arrêté avant d'utiliser cet outil.
#      Un volume attaché à un conteneur actif ne peut pas être
#      supprimé par Docker.
#
#  Usage :
#    ./volumes-rm.sh <groupe>
#
#  Groupes disponibles :
#    all       → tous les volumes du cluster
#    master    → volumes du master uniquement
#    clients   → volumes de tous les clients
#    gateways  → volumes de toutes les gateways
#    servers   → volumes de tous les servers
#    client-N  → volumes d'un client précis   (ex: client-2)
#    gateway-N → volumes d'une gateway précise (ex: gateway-1)
#    server-N  → volumes d'un server précis   (ex: server-3)
#
#  Volumes par rôle :
#    master    → sshlab_master_home, sshlab_master_etcssh
#    client-N  → sshlab_client_N_home
#    gateway-N → sshlab_gateway_N_home, sshlab_gateway_N_etcssh
#    server-N  → sshlab_server_N_home, sshlab_server_N_etcssh
#
#  Exemples :
#    ./volumes-rm.sh all          # tout supprimer
#    ./volumes-rm.sh servers      # supprimer les volumes des servers
#    ./volumes-rm.sh server-2     # supprimer les volumes de server-2 seul
#    ./volumes-rm.sh master       # supprimer les volumes du master
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/config/cluster.conf"

usage() { grep '^#  ' "$0" | sed 's/^#  \?//'; exit 0; }

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage

if [ $# -lt 1 ]; then
    echo "❌  Argument manquant."
    echo "   Usage : $(basename "$0") <groupe>"
    echo "   Aide  : $(basename "$0") --help"
    exit 1
fi

GROUP="$1"

# ── Chargement de cluster.conf ───────────────────────────────
if [ ! -f "$CONF" ]; then
    echo "❌  cluster.conf introuvable : $CONF"
    echo "   Lancez ce script depuis le répertoire ssh-lab/"
    exit 1
fi
# shellcheck source=config/cluster.conf
source "$CONF"

# ── Vérification que Docker est accessible ────────────────────
if ! docker info &>/dev/null; then
    echo "❌  Docker n'est pas accessible."
    exit 1
fi

# ── Vérification que le cluster est arrêté ───────────────────
# On inspecte les conteneurs dont le nom commence par "ssh-"
# et qui sont dans un état "running" ou "restarting".
RUNNING=$(docker ps --filter "name=ssh-" --format "{{.Names}}" 2>/dev/null || true)
if [ -n "$RUNNING" ]; then
    echo ""
    echo "❌  Des conteneurs du cluster sont encore actifs :"
    echo "$RUNNING" | while IFS= read -r c; do echo "     • $c"; done
    echo ""
    echo "   Arrêtez le cluster avant de supprimer ses volumes :"
    echo "     da down ssh-lab"
    echo ""
    exit 1
fi

# ── Fonction : volumes d'un nœud donné ───────────────────────
__volumes_of() {
    local role="$1"   # master | client | gateway | server
    local idx="$2"    # numéro (ignoré pour master)

    case "$role" in
        master)
            echo "sshlab_master_home"
            echo "sshlab_master_etcssh"
            ;;
        client)
            echo "sshlab_client_${idx}_home"
            ;;
        gateway)
            echo "sshlab_gateway_${idx}_home"
            echo "sshlab_gateway_${idx}_etcssh"
            ;;
        server)
            echo "sshlab_server_${idx}_home"
            echo "sshlab_server_${idx}_etcssh"
            ;;
    esac
}

# ── Construction de la liste des volumes à supprimer ─────────
VOLUMES=()
case "$GROUP" in
    all)
        while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of master "")
        for i in $(seq 1 "$N_CLIENTS");  do
            while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of client  "$i")
        done
        for i in $(seq 1 "$N_GATEWAYS"); do
            while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of gateway "$i")
        done
        for i in $(seq 1 "$N_SERVERS");  do
            while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of server  "$i")
        done
        ;;
    master)
        while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of master "")
        ;;
    clients)
        for i in $(seq 1 "$N_CLIENTS"); do
            while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of client "$i")
        done
        ;;
    gateways)
        for i in $(seq 1 "$N_GATEWAYS"); do
            while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of gateway "$i")
        done
        ;;
    servers)
        for i in $(seq 1 "$N_SERVERS"); do
            while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of server "$i")
        done
        ;;
    client-[0-9]*)
        IDX="${GROUP#client-}"
        while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of client "$IDX")
        ;;
    gateway-[0-9]*)
        IDX="${GROUP#gateway-}"
        while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of gateway "$IDX")
        ;;
    server-[0-9]*)
        IDX="${GROUP#server-}"
        while IFS= read -r v; do VOLUMES+=("$v"); done < <(__volumes_of server "$IDX")
        ;;
    *)
        echo "❌  Groupe ou nœud inconnu : '$GROUP'"
        echo "   Groupes : all | master | clients | gateways | servers"
        echo "   Nœuds   : client-N | gateway-N | server-N"
        exit 1
        ;;
esac

if [ "${#VOLUMES[@]}" -eq 0 ]; then
    echo "⚠️  Aucun volume pour le groupe '$GROUP'"
    exit 1
fi

# ── Filtrer : garder uniquement les volumes qui existent ──────
EXISTING=()
MISSING=()
for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" &>/dev/null 2>&1; then
        EXISTING+=("$vol")
    else
        MISSING+=("$vol")
    fi
done

# ── Affichage du plan de suppression ──────────────────────────
echo ""
printf "🗑️   volumes-rm [%s]\n" "$GROUP"
echo ""

if [ "${#EXISTING[@]}" -eq 0 ]; then
    echo "  ℹ️   Aucun volume existant à supprimer pour ce groupe."
    [ "${#MISSING[@]}" -gt 0 ] && {
        echo "  (volumes non trouvés dans Docker :)"
        for v in "${MISSING[@]}"; do printf "      • %s\n" "$v"; done
    }
    echo ""
    exit 0
fi

echo "  Volumes qui seront supprimés (données PERDUES) :"
for v in "${EXISTING[@]}"; do printf "    🔴 %s\n" "$v"; done

[ "${#MISSING[@]}" -gt 0 ] && {
    echo ""
    echo "  Volumes introuvables (déjà supprimés) :"
    for v in "${MISSING[@]}"; do printf "    ⚫ %s\n" "$v"; done
}

# ── Confirmation interactive ──────────────────────────────────
echo ""
printf "  Confirmer la suppression de %d volume(s) ? [y/N] " "${#EXISTING[@]}"
read -r CONFIRM </dev/tty
if [[ ! "$CONFIRM" =~ ^[yYoO]$ ]]; then
    echo "  Annulé."
    echo ""
    exit 0
fi

# ── Suppression ───────────────────────────────────────────────
echo ""
REMOVED=0
FAILED=0

for vol in "${EXISTING[@]}"; do
    if docker volume rm "$vol" &>/dev/null; then
        printf "  ✅  %s\n" "$vol"
        REMOVED=$(( REMOVED + 1 ))
    else
        printf "  ❌  %s — échec (volume peut-être encore utilisé ?)\n" "$vol"
        FAILED=$(( FAILED + 1 ))
    fi
done

# ── Résumé ────────────────────────────────────────────────────
echo ""
printf "  ✅ %d/%d volume(s) supprimé(s)" "$REMOVED" "${#EXISTING[@]}"
[ "$FAILED" -gt 0 ] && printf "  │  ❌ %d échec(s)" "$FAILED"
printf "\n\n"

[ "$FAILED" -eq 0 ]

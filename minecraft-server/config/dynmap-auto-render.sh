#!/usr/bin/env bash
# =============================================================================
# Watcher : dynmap-auto-render.sh
# Force périodiquement le rendu Dynmap autour des joueurs "posés" (peu mobiles).
#
# Pourquoi : Dynmap-Fabric ne supporte que les triggers `blockupdate` et
# `chunkgenerate`. Quand un joueur traverse des chunks déjà existants, aucun
# trigger ne fire → des trous apparaissent sur la carte. Ce watcher comble
# en lançant des `radiusrender` ciblés.
#
# Stratégie :
#   - Toutes les POLL_INTERVAL secondes, récupère la position des joueurs.
#   - Un joueur est "posé" si son déplacement entre 2 polls consécutifs
#     est < MOVEMENT_THRESHOLD blocs.
#   - Les joueurs posés à < CLUSTER_DISTANCE l'un de l'autre (même monde)
#     sont fusionnés en un seul cluster.
#   - Pour chaque cluster, lance un `dynmap radiusrender` autour du centroïde
#     avec un rayon scalé selon la taille du cluster.
#   - Cooldown par zone (centre arrondi à COOLDOWN_GRID) pour éviter de
#     re-rendre la même zone en boucle.
#
# Démarrage : par post-up.sh en tâche de fond.
# Arrêt    : par pre-down.sh via le PID stocké dans shared/.
# =============================================================================

set -u

CONTAINER="${CONTAINER:-minecraft_server}"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
MOVEMENT_THRESHOLD="${MOVEMENT_THRESHOLD:-32}"
CLUSTER_DISTANCE="${CLUSTER_DISTANCE:-128}"
BASE_RADIUS="${BASE_RADIUS:-192}"
PER_PLAYER_BONUS="${PER_PLAYER_BONUS:-64}"
COOLDOWN_SEC="${COOLDOWN_SEC:-300}"
COOLDOWN_GRID="${COOLDOWN_GRID:-64}"

# Le nom de la dimension overworld dépend du LEVEL configuré dans le .env
# (default: 'world' sur prod, 'test_world' sur test). Override via env :
#   OVERWORLD_WORLD=test_world ./dynmap-auto-render.sh
OVERWORLD_WORLD="${OVERWORLD_WORLD:-world}"
declare -A DIM_TO_WORLD=(
    ['minecraft:overworld']="$OVERWORLD_WORLD"
    ['minecraft:the_nether']='DIM-1'
    ['minecraft:the_end']='DIM1'
)

declare -A PREV_X PREV_Z PREV_WORLD PREV_SETTLED LAST_RENDER

log() { echo "[$(date '+%F %T')] $*"; }
rcon() { docker exec "$CONTAINER" rcon-cli "$@" 2>/dev/null; }

get_players() {
    local out
    out=$(rcon list 2>/dev/null) || return
    echo "$out" \
        | sed -nE 's/.*online: *(.*)$/\1/p' \
        | tr ',' '\n' \
        | sed 's/^ *//;s/ *$//' \
        | grep -v '^$'
}

# Echoes "x z world" (integers + dynmap world id) or nothing on failure.
get_pos_xz_world() {
    local player="$1" pos dim world x z
    pos=$(rcon "data get entity $player Pos" | grep -oE '\-?[0-9]+\.[0-9]+' | tr '\n' ' ')
    dim=$(rcon "data get entity $player Dimension" | grep -oE '"minecraft:[^"]*"' | tr -d '"')
    [ -z "$pos" ] || [ -z "$dim" ] && return
    world="${DIM_TO_WORLD[$dim]:-}"
    [ -z "$world" ] && return
    read -r x _ z _ <<< "$pos"
    echo "${x%.*} ${z%.*} $world"
}

# Integer 2D Euclidean distance.
dist() {
    awk -v dx=$(( $1 - $3 )) -v dz=$(( $2 - $4 )) \
        'BEGIN{printf "%d", sqrt(dx*dx + dz*dz)}'
}

trigger_render() {
    local world="$1" cx="$2" cz="$3" n="$4"
    local radius=$(( BASE_RADIUS + (n - 1) * PER_PLAYER_BONUS ))
    local now=$(date +%s)
    local key="${world}_$(( cx / COOLDOWN_GRID ))_$(( cz / COOLDOWN_GRID ))"
    local last="${LAST_RENDER[$key]:-0}"
    (( now - last < COOLDOWN_SEC )) && return
    LAST_RENDER[$key]=$now
    log "render world=$world center=($cx,$cz) radius=$radius cluster=$n"
    rcon "dynmap radiusrender $world $cx $cz $radius" >/dev/null
}

# Wait for the container to accept rcon commands.
log "starting dynmap-auto-render (poll=${POLL_INTERVAL}s threshold=${MOVEMENT_THRESHOLD}b cluster=${CLUSTER_DISTANCE}b)"
until rcon list >/dev/null 2>&1; do
    sleep 5
done
log "rcon reachable, entering main loop"

while sleep "$POLL_INTERVAL"; do
    declare -A SETTLED_NOW=()
    players=$(get_players) || continue
    [ -z "$players" ] && continue

    while IFS= read -r player; do
        [ -z "$player" ] && continue
        data=$(get_pos_xz_world "$player") || continue
        [ -z "$data" ] && continue
        read -r x z world <<< "$data"

        moved=999999
        if [ "${PREV_WORLD[$player]:-}" = "$world" ]; then
            moved=$(dist "$x" "$z" "${PREV_X[$player]}" "${PREV_Z[$player]}")
        fi

        currently_settled=0
        (( moved < MOVEMENT_THRESHOLD )) && currently_settled=1

        prev_settled="${PREV_SETTLED[$player]:-0}"
        if (( currently_settled && prev_settled )); then
            SETTLED_NOW[$player]="$x $z $world"
        fi

        PREV_X[$player]=$x
        PREV_Z[$player]=$z
        PREV_WORLD[$player]=$world
        PREV_SETTLED[$player]=$currently_settled
    done <<< "$players"

    # Cluster posés et déclencher un render par cluster.
    declare -A USED=()
    for p1 in "${!SETTLED_NOW[@]}"; do
        [ -n "${USED[$p1]:-}" ] && continue
        read -r x1 z1 w1 <<< "${SETTLED_NOW[$p1]}"
        cx=$x1
        cz=$z1
        n=1
        USED[$p1]=1
        for p2 in "${!SETTLED_NOW[@]}"; do
            [ "$p1" = "$p2" ] && continue
            [ -n "${USED[$p2]:-}" ] && continue
            read -r x2 z2 w2 <<< "${SETTLED_NOW[$p2]}"
            [ "$w1" != "$w2" ] && continue
            d=$(dist "$x2" "$z2" "$x1" "$z1")
            if (( d < CLUSTER_DISTANCE )); then
                cx=$(( (cx * n + x2) / (n + 1) ))
                cz=$(( (cz * n + z2) / (n + 1) ))
                n=$(( n + 1 ))
                USED[$p2]=1
            fi
        done
        trigger_render "$w1" "$cx" "$cz" "$n"
    done
done

#!/usr/bin/env bash
# =============================================================================
# Hook : dynmap-grave-marker.sh
# Démarré par post-up.sh, tué par pre-down.sh.
#
# Rôle :
# 1. Set "graves" Dynmap : sync depuis world/data/universal-graves.dat (le mod
#    universal-graves de Patbox n'a pas d'intégration Dynmap native).
# 2. Set "waystones-rich" Dynmap : version enrichie des markers waystones lus
#    depuis world/data/waystones.dat. Inclut nom + coords + dimension dans le
#    pop-up. Le set natif "waystones:waystones" reste affiché par-dessus avec
#    son label simple ; pour l'unifier, hide ce set via :
#       dmarker updateset id:"waystones:waystones" hide:true
# =============================================================================

set -e

POLL_INTERVAL="${GRAVES_POLL_INTERVAL:-30}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"
GRAVES_DAT="$SHARED_DIR/data/world/data/universal-graves.dat"
WAYSTONES_DAT="$SHARED_DIR/data/world/data/waystones.dat"
STATE_FILE="$SHARED_DIR/dynmap-grave-marker.state"
WS_STATE_FILE="$SHARED_DIR/dynmap-waystone-marker.state"
LOG_FILE="$SHARED_DIR/dynmap-grave-marker.log"

log() { echo "[$(date -u +%FT%TZ)] $*" >> "$LOG_FILE"; }

if ! command -v python3 >/dev/null; then
    log "❌ python3 introuvable, impossible de parser NBT"
    exit 1
fi

if ! python3 -c "import nbtlib" 2>/dev/null; then
    log "❌ nbtlib Python introuvable. Installer : pip3 install --user nbtlib"
    exit 1
fi

log "🪦 Watcher graves démarré (poll ${POLL_INTERVAL}s, NBT=$GRAVES_DAT)"

# Mapping Minecraft dimension → Dynmap world name
declare -A DIM_TO_WORLD=(
    [minecraft:overworld]=world
    [minecraft:the_nether]=DIM-1
    [minecraft:the_end]=DIM1
)

extract_graves() {
    # Output TSV: uuid<TAB>world<TAB>x<TAB>y<TAB>z<TAB>owner_name<TAB>created_unix<TAB>protected_until_unix
    python3 - "$GRAVES_DAT" <<'PY'
import sys, json
import nbtlib
try:
    nbt = nbtlib.load(sys.argv[1])
except Exception as e:
    print(f"# load_error: {e}", file=sys.stderr)
    sys.exit(0)

data = nbt.get('data', {})
graves = data.get('Graves', [])
for g in graves:
    g = dict(g)
    # NBT layout for universal-graves 3.10.x (Patbox) :
    #   Id (Long), Position (IntArray[3]), World (String),
    #   GameProfile{Name, Id}, CreationTime (Long), ItemCount (Int)
    grave_id = str(g.get('Id') or g.get('id') or '')
    world = str(g.get('World') or g.get('world') or '')
    pos = list(g.get('Position') or [])
    if len(pos) >= 3:
        x, y, z = int(pos[0]), int(pos[1]), int(pos[2])
    else:
        x = y = z = 0
    gp = g.get('GameProfile')
    gp = dict(gp) if hasattr(gp, 'items') else {}
    owner = str(gp.get('Name') or g.get('playerName') or '?')
    created = int(g.get('CreationTime') or g.get('creationTime') or 0)
    item_count = int(g.get('ItemCount') or 0)
    if not grave_id:
        print(f"# unknown_grave_keys: {list(g.keys())}", file=sys.stderr)
        continue
    print(f"{grave_id}\x1f{world}\x1f{x}\x1f{y}\x1f{z}\x1f{owner}\x1f{created}\x1f{item_count}")
PY
}

dmarker() {
    docker exec minecraft_server rcon-cli "$@" >/dev/null 2>&1
}

ensure_set() {
    docker exec minecraft_server rcon-cli "dmarker listsets" 2>/dev/null | grep -q '^graves:\|graves: ' || \
        docker exec minecraft_server rcon-cli 'dmarker addset id:graves label:"Tombes" prio:5 deficon:skull' >/dev/null 2>&1
}

sync_once() {
    [ -f "$GRAVES_DAT" ] || { log "graves.dat absent, skip"; return; }
    ensure_set

    local current_tsv="$STATE_FILE.new"
    if ! extract_graves > "$current_tsv" 2> >(grep -v '^# unknown_grave_keys' >> "$LOG_FILE"); then
        log "extract_graves a échoué"
        rm -f "$current_tsv"
        return
    fi

    [ -f "$STATE_FILE" ] || touch "$STATE_FILE"

    local current_uuids previous_uuids
    current_uuids="$(cut -d $'\x1f' -f1 "$current_tsv" | sort -u)"
    previous_uuids="$(cut -d $'\x1f' -f1 "$STATE_FILE" | sort -u)"

    # Removed: in previous, not in current → dmarker delete
    while IFS= read -r uuid; do
        [ -z "$uuid" ] && continue
        log "🗑️  grave removed: $uuid"
        dmarker "dmarker delete id:grave-$uuid set:graves"
    done < <(comm -23 <(echo "$previous_uuids") <(echo "$current_uuids"))

    # Added: in current, not in previous → dmarker add
    while IFS=$'\x1f' read -r grave_id world x y z owner created item_count; do
        local dynworld="${DIM_TO_WORLD[$world]:-$world}"
        [ -n "$grave_id" ] || continue
        # Skip if already in previous
        echo "$previous_uuids" | grep -qx "$grave_id" && continue
        local label
        if [ "$item_count" -gt 0 ] 2>/dev/null; then
            label="Tombe de ${owner} (${x}, ${y}, ${z}) — ${item_count} item(s)"
        else
            label="Tombe de ${owner} (${x}, ${y}, ${z})"
        fi
        log "➕ grave added: $grave_id → $dynworld ($x,$y,$z) [$owner, ${item_count} items]"
        dmarker "dmarker add id:grave-$grave_id set:graves icon:skull label:\"$label\" world:$dynworld x:$x y:$y z:$z"
    done < "$current_tsv"

    mv "$current_tsv" "$STATE_FILE"
}

extract_waystones() {
    # Output TSV: uuid<TAB>world<TAB>x<TAB>y<TAB>z<TAB>name<TAB>visibility<TAB>origin
    python3 - "$WAYSTONES_DAT" <<'PY'
import sys, struct
import nbtlib
try:
    nbt = nbtlib.load(sys.argv[1])
except Exception as e:
    print(f"# load_error: {e}", file=sys.stderr)
    sys.exit(0)

def uid_to_uuid(arr):
    if not arr or len(arr) != 4:
        return ""
    # 4 ints (signed 32-bit) → 128-bit UUID
    bytes_ = b''.join(struct.pack('>i', int(x)) for x in arr)
    h = bytes_.hex()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"

data = nbt.get('data', {})
waystones = data.get('Waystones', [])
for w in waystones:
    w = dict(w)
    if str(w.get('Type','')) != 'waystones:waystone':
        continue  # skip sharestones / other types
    uid = uid_to_uuid(list(w.get('WaystoneUid', [])))
    pos = list(w.get('BlockPos', []))
    if len(pos) != 3 or not uid:
        continue
    x, y, z = int(pos[0]), int(pos[1]), int(pos[2])
    world = str(w.get('World') or '')
    name = str(w.get('NameV2') or w.get('Name') or '')
    vis = str(w.get('Visibility') or 'activation')
    origin = str(w.get('Origin') or '')
    print(f"{uid}\x1f{world}\x1f{x}\x1f{y}\x1f{z}\x1f{name}\x1f{vis}\x1f{origin}")
PY
}

ensure_waystone_set() {
    docker exec minecraft_server rcon-cli "dmarker listsets" 2>/dev/null | grep -q '^waystones-rich:\|waystones-rich: ' || \
        docker exec minecraft_server rcon-cli 'dmarker addset id:waystones-rich label:"Waystones" prio:4 deficon:portal' >/dev/null 2>&1
}

sync_waystones() {
    [ -f "$WAYSTONES_DAT" ] || return
    ensure_waystone_set

    local current_tsv="$WS_STATE_FILE.new"
    if ! extract_waystones > "$current_tsv" 2>>"$LOG_FILE"; then
        rm -f "$current_tsv"
        return
    fi

    [ -f "$WS_STATE_FILE" ] || touch "$WS_STATE_FILE"

    # Build maps of uuid → row for current and previous
    declare -A cur_row prev_row
    while IFS=$'\x1f' read -r uuid rest; do
        [ -n "$uuid" ] && cur_row[$uuid]="$rest"
    done < "$current_tsv"
    while IFS=$'\x1f' read -r uuid rest; do
        [ -n "$uuid" ] && prev_row[$uuid]="$rest"
    done < "$WS_STATE_FILE"

    # Removed
    for uuid in "${!prev_row[@]}"; do
        if [ -z "${cur_row[$uuid]+x}" ]; then
            log "🗑️  waystone removed: $uuid"
            dmarker "dmarker delete id:waystone-$uuid set:waystones-rich"
        fi
    done

    # Added or changed
    for uuid in "${!cur_row[@]}"; do
        # Skip if exact same row as last poll
        [ "${cur_row[$uuid]}" = "${prev_row[$uuid]:-}" ] && continue
        IFS=$'\x1f' read -r world x y z name vis origin <<< "${cur_row[$uuid]}"
        local dynworld="${DIM_TO_WORLD[$world]:-$world}"
        local label
        if [ -n "$name" ]; then
            label="${name} (${x}, ${y}, ${z})"
        elif [ "$origin" = "wilderness" ]; then
            label="Waystone sauvage (${x}, ${y}, ${z})"
        else
            label="Waystone (${x}, ${y}, ${z})"
        fi
        if [ -z "${prev_row[$uuid]+x}" ]; then
            log "➕ waystone added: $uuid → $dynworld ($x,$y,$z) [$name|$origin|$vis]"
            dmarker "dmarker add id:waystone-$uuid set:waystones-rich icon:portal label:\"$label\" world:$dynworld x:$x y:$y z:$z"
        else
            log "✏️  waystone updated: $uuid → label=\"$label\""
            dmarker "dmarker update id:waystone-$uuid set:waystones-rich label:\"$label\" world:$dynworld x:$x y:$y z:$z"
        fi
    done

    mv "$current_tsv" "$WS_STATE_FILE"
}

trap 'log "🛑 watcher arrêté"; exit 0' INT TERM

while true; do
    sync_once || log "sync graves error (continuing)"
    sync_waystones || log "sync waystones error (continuing)"
    sleep "$POLL_INTERVAL"
done

#!/usr/bin/env bash
# ============================================================
#  pre-up.sh — Génère docker-compose.yaml depuis
#              topology.conf (machines) + box.conf (réseau/IHM).
#  Exécuté automatiquement par : da up net-lab
#  NE JAMAIS éditer docker-compose.yaml à la main.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPO="$SCRIPT_DIR/topology.conf"
BOXCONF="$SCRIPT_DIR/box.conf"
OUTPUT="$SCRIPT_DIR/docker-compose.yaml"
SHARED="$SCRIPT_DIR/../shared"

# ── Chargement de la configuration ───────────────────────────
[ -f "$TOPO" ]    || { echo "❌  introuvable : $TOPO"; exit 1; }
[ -f "$BOXCONF" ] || { echo "❌  introuvable : $BOXCONF"; exit 1; }
# shellcheck source=topology.conf
source "$TOPO"
# shellcheck source=box.conf
source "$BOXCONF"

# ── Validation ────────────────────────────────────────────────
for var in N_SERVERS N_CLIENTS; do
    val="${!var:-}"
    [[ "$val" =~ ^[0-9]+$ ]] || { echo "❌  $var doit être un entier >= 0 (reçu : '${val}')"; exit 1; }
done
[ -n "${ROOT_PASSWORD:-}" ] || { echo "❌  ROOT_PASSWORD non défini (topology.conf)"; exit 1; }
[ -n "${PUBLIC_IP:-}" ]    || { echo "❌  PUBLIC_IP non défini (box.conf)"; exit 1; }
for var in WAN_SUBNET LAN_SUBNET DMZ_SUBNET; do
    [ -n "${!var:-}" ] || { echo "❌  $var non défini (box.conf)"; exit 1; }
done
VALID_LOG="QUIET FATAL ERROR INFO VERBOSE DEBUG DEBUG1 DEBUG2 DEBUG3"
echo "$VALID_LOG" | grep -qw "${LOG_LEVEL:-}" || { echo "❌  LOG_LEVEL invalide : '${LOG_LEVEL:-}'"; exit 1; }

# ── Plan d'adressage ─────────────────────────────────────────
WAN_PFX="$(echo "$WAN_SUBNET" | cut -d/ -f1 | cut -d. -f1-3)"
LAN_PFX="$(echo "$LAN_SUBNET" | cut -d/ -f1 | cut -d. -f1-3)"
DMZ_PFX="$(echo "$DMZ_SUBNET" | cut -d/ -f1 | cut -d. -f1-3)"

WAN_GW="$WAN_PFX.1"          # passerelle bridge Docker (egress Internet des clients)
LAN_GW="$LAN_PFX.254"        # bridge Docker (egress Internet du LAN) — la box prend .1
DMZ_GW="$DMZ_PFX.254"        # bridge Docker (egress Internet de la DMZ) — la box prend .1
BOX_LAN="$LAN_PFX.1"
BOX_DMZ="$DMZ_PFX.1"

# Cherche un bail statique "nom:ip", sinon renvoie la valeur par défaut.
lease_ip() {
    local name="$1" def="$2" l
    for l in "${LEASES[@]:-}"; do
        [ -n "$l" ] && [ "${l%%:*}" = "$name" ] && { echo "${l#*:}"; return; }
    done
    echo "$def"
}

# ── Résolution des IP de chaque machine + HOSTMAP ────────────
declare -a NAMES
HOSTMAP=""
add_host() { NAMES+=("$1"); HOSTMAP+="${HOSTMAP:+;}$1=$2"; }

GW_IP="$(lease_ip gateway "$LAN_PFX.10")"
add_host "gateway" "$GW_IP"
for i in $(seq 1 "$N_SERVERS"); do
    add_host "server-$i" "$(lease_ip "server-$i" "$LAN_PFX.$((20 + i - 1))")"
done
NAS_IP="$(lease_ip nas "$DMZ_PFX.10")"
add_host "nas" "$NAS_IP"
for i in $(seq 1 "$N_CLIENTS"); do
    add_host "client-$i" "$(lease_ip "client-$i" "$WAN_PFX.$((101 + i - 1))")"
done

# ── Répertoires partagés (uploads + config appliquée box) ────
mkdir -p "$SHARED/box" \
         "$SHARED/uploads/all" "$SHARED/uploads/nas" "$SHARED/uploads/gateway" \
         "$SHARED/uploads/servers" "$SHARED/uploads/clients"
# Copie de la config "appliquée" que la box lit réellement (l'IHM pousse ici).
cp "$BOXCONF" "$SHARED/box/box.conf"

echo ""
echo "🔧  Génération docker-compose.yaml"
echo "     box      : $PUBLIC_IP (wan) | $BOX_LAN (lan) | $BOX_DMZ (dmz)"
echo "     gateway  : $GW_IP   |  nas : $NAS_IP"
echo "     servers  : $N_SERVERS   |  clients : $N_CLIENTS"
echo "     LogLevel : $LOG_LEVEL"
echo ""

# ══════════════════════════════════════════════════════════════
#  Helper d'émission d'un service "node"
#  $1 name  $2 role  $3 network  $4 ip  $5 uploads_group  $6 lan(0/1)
# ══════════════════════════════════════════════════════════════
emit_node() {
    local name="$1" role="$2" net="$3" ip="$4" grp="$5" lan="$6"
    cat << EOF

  $name:
    build:
      context: ./node
    container_name: net-lab-$name
    hostname: $name
    networks:
      $net:
        ipv4_address: $ip
    environment:
      - NODE_ROLE=$role
      - NODE_NAME=$name
      - ROOT_PASSWORD=${ROOT_PASSWORD}
      - LOG_LEVEL=${LOG_LEVEL}
EOF
    if [ "$lan" = "1" ]; then
        cat << EOF
      - DMZ_SUBNET=${DMZ_SUBNET}
      - BOX_LAN_IP=${BOX_LAN}
    cap_add:
      - NET_ADMIN
EOF
    fi
    cat << EOF
    volumes:
      - netlab_${name}_home:/root
      - netlab_${name}_etcssh:/etc/ssh
      - ../shared/uploads/all:/uploads/all:ro
      - ../shared/uploads/${grp}:/uploads/role:ro
    restart: unless-stopped
    tty: true
    stdin_open: true
EOF
}

# ══════════════════════════════════════════════════════════════
#  Génération du fichier
# ══════════════════════════════════════════════════════════════
{
cat << EOF
# ============================================================
# AUTO-GÉNÉRÉ par pre-up.sh — NE PAS MODIFIER À LA MAIN
# Éditez config/topology.conf ou config/box.conf puis :
#   da restart net-lab
# ============================================================

networks:

  # WAN : "Internet". IP publique de la box + clients extérieurs.
  wan:
    driver: bridge
    ipam:
      config:
        - subnet: ${WAN_SUBNET}
          gateway: ${WAN_GW}

  # LAN : réseau domestique (gateway + servers). Box = ${BOX_LAN}.
  lan:
    driver: bridge
    ipam:
      config:
        - subnet: ${LAN_SUBNET}
          gateway: ${LAN_GW}

  # DMZ : segment isolé du NAS. Box = ${BOX_DMZ}.
  dmz:
    driver: bridge
    ipam:
      config:
        - subnet: ${DMZ_SUBNET}
          gateway: ${DMZ_GW}

services:

  # ── BOX (routeur NAT / pare-feu) ────────────────────────────
  box:
    build:
      context: ./box
    container_name: net-lab-box
    hostname: box
    networks:
      wan:
        ipv4_address: ${PUBLIC_IP}
      lan:
        ipv4_address: ${BOX_LAN}
      dmz:
        ipv4_address: ${BOX_DMZ}
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      - HOSTMAP=${HOSTMAP}
    volumes:
      - ../shared/box/box.conf:/etc/net-lab/box.conf:ro
    restart: unless-stopped
    tty: true
    stdin_open: true
EOF

echo ""
echo "  # ── GATEWAY (LAN, entrée des artistes) ──────────────────────"
emit_node "gateway" "gateway" "lan" "$GW_IP" "gateway" 1

if [ "$N_SERVERS" -gt 0 ]; then
    echo ""
    echo "  # ── SERVERS (LAN) ───────────────────────────────────────────"
    for i in $(seq 1 "$N_SERVERS"); do
        emit_node "server-$i" "server" "lan" "$(lease_ip "server-$i" "$LAN_PFX.$((20 + i - 1))")" "servers" 1
    done
fi

echo ""
echo "  # ── NAS (DMZ) ───────────────────────────────────────────────"
emit_node "nas" "nas" "dmz" "$NAS_IP" "nas" 0

if [ "$N_CLIENTS" -gt 0 ]; then
    echo ""
    echo "  # ── CLIENTS (WAN) ───────────────────────────────────────────"
    for i in $(seq 1 "$N_CLIENTS"); do
        emit_node "client-$i" "client" "wan" "$(lease_ip "client-$i" "$WAN_PFX.$((101 + i - 1))")" "clients" 0
    done
fi

echo ""
echo "# ── Volumes nommés (préfixe netlab_) ────────────────────────"
echo "volumes:"
for n in "${NAMES[@]}"; do
    echo "  netlab_${n}_home:"
    echo "    name: netlab_${n}_home"
    echo "  netlab_${n}_etcssh:"
    echo "    name: netlab_${n}_etcssh"
done

} > "$OUTPUT"

echo "✅  docker-compose.yaml généré → $OUTPUT"
echo "🗺️   HOSTMAP : $HOSTMAP"
echo ""

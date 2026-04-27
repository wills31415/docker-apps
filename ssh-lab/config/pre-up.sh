#!/usr/bin/env bash
# ============================================================
#  pre-up.sh — Génère docker-compose.yaml depuis cluster.conf
#              + génère la clé SSH admin du MASTER (idempotent)
#  Exécuté automatiquement par : da up ssh-lab
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/cluster.conf"
OUTPUT="$SCRIPT_DIR/docker-compose.yaml"
ADMIN_KEY_DIR="$SCRIPT_DIR/../shared/admin-key"
ADMIN_KEY="$ADMIN_KEY_DIR/id_admin"
ADMIN_PUBKEY="$ADMIN_KEY_DIR/id_admin.pub"

# ── Chargement de la configuration ───────────────────────────
if [ ! -f "$CONF" ]; then
    echo "❌  Fichier de configuration introuvable : $CONF"
    exit 1
fi
# shellcheck source=cluster.conf
source "$CONF"

# ── Validation ────────────────────────────────────────────────
for var in N_CLIENTS N_GATEWAYS N_SERVERS SSH_PORT_BASE; do
    val="${!var:-}"
    if ! [[ "$val" =~ ^[1-9][0-9]*$ ]]; then
        echo "❌  Variable $var invalide : '${val}' — entier >= 1 attendu"
        exit 1
    fi
done
if [ -z "${ROOT_PASSWORD:-}" ]; then
    echo "❌  ROOT_PASSWORD n'est pas défini dans cluster.conf"
    exit 1
fi
if [ -z "${ADMIN_PASSWORD:-}" ]; then
    echo "❌  ADMIN_PASSWORD n'est pas défini dans cluster.conf"
    exit 1
fi
VALID_LOG_LEVELS="QUIET FATAL ERROR INFO VERBOSE DEBUG DEBUG1 DEBUG2 DEBUG3"
if ! echo "$VALID_LOG_LEVELS" | grep -qw "${LOG_LEVEL:-}"; then
    echo "❌  LOG_LEVEL invalide : '${LOG_LEVEL:-}'"
    echo "   Valeurs acceptées : $VALID_LOG_LEVELS"
    exit 1
fi

echo ""
echo "🔧  Génération de docker-compose.yaml depuis cluster.conf…"
echo "     CLIENTs  : $N_CLIENTS"
echo "     GATEWAYs : $N_GATEWAYS  (ports hôte $(( SSH_PORT_BASE + 1 ))–$(( SSH_PORT_BASE + N_GATEWAYS )) → 22)"
echo "     SERVERs  : $N_SERVERS"
echo "     MASTER   : 1 (fixe, toujours présent)"
echo "     LogLevel : $LOG_LEVEL"
echo ""

# ── Création des répertoires ──────────────────────────────────
mkdir -p \
    "$SCRIPT_DIR/../shared/uploads/all" \
    "$SCRIPT_DIR/../shared/uploads/master" \
    "$SCRIPT_DIR/../shared/uploads/clients" \
    "$SCRIPT_DIR/../shared/uploads/gateways" \
    "$SCRIPT_DIR/../shared/uploads/servers" \
    "$ADMIN_KEY_DIR"

# ══════════════════════════════════════════════════════════════
# Génération de la clé SSH admin (idempotente)
# La clé est stockée dans shared/admin-key/ et distribuée via
# bind-mount en lecture seule dans tous les conteneurs.
# Elle n'est régénérée que si elle est absente ou invalide.
# ══════════════════════════════════════════════════════════════
if [ -f "$ADMIN_KEY" ] && [ -f "$ADMIN_PUBKEY" ] \
   && ssh-keygen -l -f "$ADMIN_KEY" &>/dev/null; then
    echo "🔑  Clé admin existante réutilisée : $ADMIN_KEY"
    echo "    $(ssh-keygen -l -f "$ADMIN_KEY")"
else
    echo "🔑  Génération de la clé SSH admin (ed25519)…"
    rm -f "$ADMIN_KEY" "$ADMIN_PUBKEY"
    ssh-keygen -t ed25519 \
        -f "$ADMIN_KEY" \
        -N "" \
        -C "ssh-lab-admin@master" \
        -q
    chmod 600 "$ADMIN_KEY"
    chmod 644 "$ADMIN_PUBKEY"
    echo "    ✅  Clé générée : $ADMIN_KEY"
    echo "    $(ssh-keygen -l -f "$ADMIN_KEY")"
fi
echo ""

# ══════════════════════════════════════════════════════════════
# Génération du docker-compose.yaml
#
# Volumes nommés (préfixe sshlab_) :
#   sshlab_{role}_{N}_home    → /root    (tous)
#   sshlab_{role}_{N}_etcssh  → /etc/ssh (gateway + server + master)
#
# Bind-mounts partagés (lecture seule) :
#   ../shared/admin-key → /admin-key  dans TOUS les conteneurs
#   ../shared/uploads/… → /uploads/…  dans TOUS les conteneurs
# ══════════════════════════════════════════════════════════════
{

cat << 'HEADER'
# ============================================================
# AUTO-GÉNÉRÉ par pre-up.sh — NE PAS MODIFIER MANUELLEMENT
# Modifiez config/cluster.conf puis relancez : da restart ssh-lab
# ============================================================

networks:

  # Réseau frontal : CLIENTs + GATEWAYs + MASTER
  client-net:
    driver: bridge

  # Réseau des SERVERs + GATEWAYs + MASTER
  # PAS d'internal: true → les SERVERs ont accès à Internet (apk, curl…)
  # L'isolation SSH est garantie TOPOLOGIQUEMENT : CLIENTs et SERVERs ne
  # partagent aucun réseau commun, donc aucune route directe entre eux.
  # Le seul chemin SSH vers les SERVERs passe par une GATEWAY (jump host).
  server-net:
    driver: bridge

services:

HEADER

# ─── MASTER (toujours présent, hardcodé) ─────────────────────
echo "# ── MASTER ──────────────────────────────────────────────────"
cat << EOF

  master:
    build:
      context: ./master
    container_name: ssh-master
    hostname: master
    networks:
      - client-net
      - server-net
    environment:
      - ROOT_PASSWORD=${ROOT_PASSWORD}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - NODE_ROLE=master
      - NODE_INDEX=1
      - LOG_LEVEL=${LOG_LEVEL}
      - N_CLIENTS=${N_CLIENTS}
      - N_GATEWAYS=${N_GATEWAYS}
      - N_SERVERS=${N_SERVERS}
    volumes:
      # Volumes nommés — persistence
      - sshlab_master_home:/root
      - sshlab_master_etcssh:/etc/ssh
      # Clé admin en lecture seule (private + public)
      - ../shared/admin-key:/admin-key:ro
      # Uploads depuis l'hôte
      - ../shared/uploads/all:/uploads/all:ro
      - ../shared/uploads/master:/uploads/role:ro
    stop_signal: SIGTERM
    restart: unless-stopped
    tty: true
    stdin_open: true

EOF

# ─── CLIENTs ─────────────────────────────────────────────────
echo "# ── CLIENTs ─────────────────────────────────────────────────"
for i in $(seq 1 "$N_CLIENTS"); do
cat << EOF

  client-$i:
    build:
      context: ./client
    container_name: ssh-client-$i
    hostname: client-$i
    networks:
      - client-net
    environment:
      - ROOT_PASSWORD=${ROOT_PASSWORD}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - NODE_ROLE=client
      - NODE_INDEX=$i
      - LOG_LEVEL=${LOG_LEVEL}
    volumes:
      - sshlab_client_${i}_home:/root
      - ../shared/admin-key:/admin-key:ro
      - ../shared/uploads/all:/uploads/all:ro
      - ../shared/uploads/clients:/uploads/role:ro
    stop_signal: SIGTERM
    restart: unless-stopped
    tty: true
    stdin_open: true
EOF
done

# ─── GATEWAYs ────────────────────────────────────────────────
echo ""
echo "# ── GATEWAYs ────────────────────────────────────────────────"
for i in $(seq 1 "$N_GATEWAYS"); do
    host_port=$(( SSH_PORT_BASE + i ))
cat << EOF

  gateway-$i:
    build:
      context: ./gateway
    container_name: ssh-gateway-$i
    hostname: gateway-$i
    networks:
      - client-net
      - server-net
    ports:
      - "${host_port}:22"
    environment:
      - ROOT_PASSWORD=${ROOT_PASSWORD}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - NODE_ROLE=gateway
      - NODE_INDEX=$i
      - LOG_LEVEL=${LOG_LEVEL}
    volumes:
      - sshlab_gateway_${i}_home:/root
      - sshlab_gateway_${i}_etcssh:/etc/ssh
      - ../shared/admin-key:/admin-key:ro
      - ../shared/uploads/all:/uploads/all:ro
      - ../shared/uploads/gateways:/uploads/role:ro
    stop_signal: SIGTERM
    restart: unless-stopped
    tty: true
    stdin_open: true
EOF
done

# ─── SERVERs ─────────────────────────────────────────────────
echo ""
echo "# ── SERVERs ─────────────────────────────────────────────────"
for i in $(seq 1 "$N_SERVERS"); do
cat << EOF

  server-$i:
    build:
      context: ./server
    container_name: ssh-server-$i
    hostname: server-$i
    networks:
      - server-net
    environment:
      - ROOT_PASSWORD=${ROOT_PASSWORD}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - NODE_ROLE=server
      - NODE_INDEX=$i
      - LOG_LEVEL=${LOG_LEVEL}
    volumes:
      - sshlab_server_${i}_home:/root
      - sshlab_server_${i}_etcssh:/etc/ssh
      - ../shared/admin-key:/admin-key:ro
      - ../shared/uploads/all:/uploads/all:ro
      - ../shared/uploads/servers:/uploads/role:ro
    stop_signal: SIGTERM
    restart: unless-stopped
    tty: true
    stdin_open: true
EOF
done

# ─── Section volumes nommés ───────────────────────────────────
# Chaque volume déclare un champ "name:" explicite.
# Sans cela, Docker Compose préfixe automatiquement le nom avec
# le répertoire contenant le fichier compose (ici "config_"),
# ce qui donnerait "config_sshlab_master_home" au lieu de
# "sshlab_master_home". Le champ "name:" désactive ce préfixage.
echo ""
echo "# ── Volumes nommés ──────────────────────────────────────────"
echo "volumes:"

echo ""
echo "  # MASTER"
echo "  sshlab_master_home:"
echo "    name: sshlab_master_home"
echo "  sshlab_master_etcssh:"
echo "    name: sshlab_master_etcssh"

echo ""
echo "  # CLIENTs — /root"
for i in $(seq 1 "$N_CLIENTS"); do
    echo "  sshlab_client_${i}_home:"
    echo "    name: sshlab_client_${i}_home"
done

echo ""
echo "  # GATEWAYs — /root + /etc/ssh"
for i in $(seq 1 "$N_GATEWAYS"); do
    echo "  sshlab_gateway_${i}_home:"
    echo "    name: sshlab_gateway_${i}_home"
    echo "  sshlab_gateway_${i}_etcssh:"
    echo "    name: sshlab_gateway_${i}_etcssh"
done

echo ""
echo "  # SERVERs — /root + /etc/ssh"
for i in $(seq 1 "$N_SERVERS"); do
    echo "  sshlab_server_${i}_home:"
    echo "    name: sshlab_server_${i}_home"
    echo "  sshlab_server_${i}_etcssh:"
    echo "    name: sshlab_server_${i}_etcssh"
done

} > "$OUTPUT"

echo "✅  docker-compose.yaml généré → $OUTPUT"
echo ""
total_vols=$(( 2 + N_CLIENTS + N_GATEWAYS * 2 + N_SERVERS * 2 ))
echo "📦  $total_vols volumes nommés  |  préfixe : sshlab_"
echo "🔑  Clé admin : shared/admin-key/id_admin{,.pub}"
echo ""

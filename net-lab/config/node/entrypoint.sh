#!/usr/bin/env bash
# ============================================================
#  Entrypoint — NODE (nas / gateway / server / client)
#  Variables :
#    NODE_ROLE, NODE_NAME, ROOT_PASSWORD, LOG_LEVEL
#    (LAN uniquement) DMZ_SUBNET + BOX_LAN_IP → route vers la DMZ
#    (LAN+DMZ) BOX_GW_IP + EGRESS_VIA_BOX → passerelle par défaut = box
# ============================================================
set -euo pipefail

NODE_ROLE="${NODE_ROLE:-server}"
NODE_NAME="${NODE_NAME:-$NODE_ROLE}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# ── 1. Mot de passe root ──────────────────────────────────────
[ -n "${ROOT_PASSWORD:-}" ] && echo "root:${ROOT_PASSWORD}" | chpasswd

# ── 2. Configuration et clés sshd ─────────────────────────────
mkdir -p /run/sshd /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config << SSHD_CONF
Port 22
AddressFamily any
ListenAddress 0.0.0.0

PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
PubkeyAuthentication yes

UseDNS no
PrintMotd no
LogLevel ${LOG_LEVEL}

Subsystem sftp /usr/lib/openssh/sftp-server

# Ce fichier est régénéré à chaque boot ; les drop-ins de
# /etc/ssh/sshd_config.d/ (volume /etc/ssh persistant) survivent, eux. Inclus
# en FIN de config pour qu'un bloc Match d'un drop-in ne fuite pas dans la
# config de base. Dossier vide par défaut → aucun changement de comportement.
Include /etc/ssh/sshd_config.d/*.conf
SSHD_CONF
ssh-keygen -A >/dev/null 2>&1

# ── 3. Routage ────────────────────────────────────────────────
# (a) Nodes du LAN : route spécifique vers la DMZ via la box. Présente
#     dans les DEUX modes — c'est elle qui fait fonctionner LAN→DMZ.
if [ -n "${DMZ_SUBNET:-}" ] && [ -n "${BOX_LAN_IP:-}" ]; then
    if ip route replace "$DMZ_SUBNET" via "$BOX_LAN_IP" 2>/dev/null; then
        echo "✔  route $DMZ_SUBNET via la box ($BOX_LAN_IP)"
    else
        echo "⚠️  route DMZ non ajoutée (cap NET_ADMIN manquante ?)"
    fi
fi
# (b) Mode EGRESS_VIA_BOX=1 : la box devient la passerelle PAR DÉFAUT.
#     Tout le trafic (Internet compris) traverse alors la box → source
#     réelle préservée + point de contrôle unique. Sinon Docker reste
#     la passerelle par défaut (egress direct).
if [ "${EGRESS_VIA_BOX:-0}" = "1" ] && [ -n "${BOX_GW_IP:-}" ]; then
    if ip route replace default via "$BOX_GW_IP" 2>/dev/null; then
        echo "✔  passerelle par défaut → box ($BOX_GW_IP)  [EGRESS_VIA_BOX=1]"
    else
        echo "⚠️  bascule passerelle par défaut échouée (cap NET_ADMIN ?)"
    fi
fi

# ── 4. Service HTTP de démo (NAS uniquement) ──────────────────
if [ "$NODE_ROLE" = "nas" ]; then
    mkdir -p /srv/www
    if [ ! -f /srv/www/index.html ]; then
        cat > /srv/www/index.html << 'HTML'
<!doctype html>
<title>net-lab NAS</title>
<h1>net-lab — NAS (DMZ)</h1>
<p>Si tu lis ceci à travers la box, le DNAT fonctionne.</p>
HTML
    fi
    ( cd /srv/www && exec python3 -m http.server 8080 ) &
    echo "✔  serveur HTTP démo sur :8080  (/srv/www)"
fi

# ── 5. Bannière ───────────────────────────────────────────────
case "$NODE_ROLE" in
    nas)     ICON="🗄️ " ; NET="DMZ" ;;
    gateway) ICON="🚪" ; NET="LAN (entrée des artistes)" ;;
    server)  ICON="🖥️ " ; NET="LAN" ;;
    client)  ICON="💻" ; NET="WAN (extérieur)" ;;
    *)       ICON="❔" ; NET="?" ;;
esac
echo ""
echo "┌──────────────────────────────────────────────────┐"
printf "│  %s  %-12s démarré  (%s)\n" "$ICON" "$NODE_NAME" "$NET"
printf "│  root : mot de passe  │  sshd LogLevel %-7s │\n" "$LOG_LEVEL"
echo "└──────────────────────────────────────────────────┘"
echo ""

# ── 6. sshd au premier plan ───────────────────────────────────
exec /usr/sbin/sshd -D -e

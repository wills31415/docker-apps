#!/usr/bin/env bash
# ============================================================
#  Entrypoint — NODE (nas / gateway / server / client)
#
#  Sémantique : on simule une vraie machine, pas un conteneur jetable.
#    • Phase 1 (FIRST BOOT) — provisioning. Garde par marker
#      /var/lib/net-lab/.provisioned. Tourne uniquement quand le
#      writable layer est neuf (i.e. après un `da up` sur un conteneur
#      nouvellement créé, jamais après un soft restart).
#    • Phase 2 (CHAQUE BOOT) — runtime. Idempotent. Pose les routes
#      réseau (recréées avec le namespace), lance le HTTP demo NAS et
#      sshd.
#
#  Variables :
#    env (set à compose create, structurelles) :
#      NODE_ROLE, NODE_NAME
#      (LAN)     DMZ_SUBNET + BOX_LAN_IP → route vers la DMZ
#      (LAN+DMZ) BOX_GW_IP + EGRESS_VIA_BOX → passerelle par défaut
#    /net-lab/runtime.conf (bind-monté, hot-tunable via reprovision.sh) :
#      ROOT_PASSWORD, LOG_LEVEL
# ============================================================
set -euo pipefail

NODE_ROLE="${NODE_ROLE:-server}"
NODE_NAME="${NODE_NAME:-$NODE_ROLE}"

# Runtime config hot-tunable, écrite par pre-up.sh depuis topology.conf et
# bind-montée ro à chaque container start. Source de vérité pour les
# valeurs admin-tunables sans recreate (./reprovision.sh re-source ce fichier).
RUNTIME_CONF=/net-lab/runtime.conf
if [ -f "$RUNTIME_CONF" ]; then
    # shellcheck disable=SC1090
    source "$RUNTIME_CONF"
fi
LOG_LEVEL="${LOG_LEVEL:-INFO}"

MARKER=/var/lib/net-lab/.provisioned

# ══════════════════════════════════════════════════════════════
#  PHASE 1 — FIRST BOOT (provisioning)
# ══════════════════════════════════════════════════════════════
if [ ! -f "$MARKER" ]; then
    mkdir -p /var/lib/net-lab /etc/ssh/sshd_config.d /run/sshd

    # ── Mot de passe root ────────────────────────────────────
    [ -n "${ROOT_PASSWORD:-}" ] && echo "root:${ROOT_PASSWORD}" | chpasswd

    # ── Config sshd de base (Include en TÊTE, convention Debian :
    #    1ʳᵉ occurrence gagne ⇒ les drop-ins peuvent overrider).
    cat > /etc/ssh/sshd_config << SSHD_CONF
Port 22
Include /etc/ssh/sshd_config.d/*.conf
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
SSHD_CONF

    # ── Clés d'hôte sshd (générées une seule fois) ──────────
    ssh-keygen -A >/dev/null 2>&1

    # ── Démo NAS : page HTML servie par http.server ────────
    if [ "$NODE_ROLE" = "nas" ]; then
        mkdir -p /srv/www
        cat > /srv/www/index.html << 'HTML'
<!doctype html>
<title>net-lab NAS</title>
<h1>net-lab — NAS (DMZ)</h1>
<p>Si tu lis ceci à travers la box, le DNAT fonctionne.</p>
HTML
    fi

    touch "$MARKER"
    echo "✔  provisioning initial effectué (marker : $MARKER)"
fi

# ══════════════════════════════════════════════════════════════
#  PHASE 2 — CHAQUE BOOT (runtime)
# ══════════════════════════════════════════════════════════════

# /run est tmpfs ⇒ vide à chaque démarrage
mkdir -p /run/sshd

# ── Routage ─────────────────────────────────────────────────
# (a) LAN : route spécifique vers la DMZ via la box. Présente dans
#     les DEUX modes — c'est elle qui fait fonctionner LAN→DMZ.
if [ -n "${DMZ_SUBNET:-}" ] && [ -n "${BOX_LAN_IP:-}" ]; then
    if ip route replace "$DMZ_SUBNET" via "$BOX_LAN_IP" 2>/dev/null; then
        echo "✔  route $DMZ_SUBNET via la box ($BOX_LAN_IP)"
    else
        echo "⚠️  route DMZ non ajoutée (cap NET_ADMIN manquante ?)"
    fi
fi
# (b) EGRESS_VIA_BOX=1 : box = passerelle par défaut. Tout le trafic
#     (Internet inclus) traverse la box → source réelle préservée +
#     point de contrôle unique. Sinon Docker reste la passerelle.
if [ "${EGRESS_VIA_BOX:-0}" = "1" ] && [ -n "${BOX_GW_IP:-}" ]; then
    if ip route replace default via "$BOX_GW_IP" 2>/dev/null; then
        echo "✔  passerelle par défaut → box ($BOX_GW_IP)  [EGRESS_VIA_BOX=1]"
    else
        echo "⚠️  bascule passerelle par défaut échouée (cap NET_ADMIN ?)"
    fi
fi

# ── Service HTTP de démo (NAS uniquement) ─────────────────
if [ "$NODE_ROLE" = "nas" ]; then
    ( cd /srv/www && exec python3 -m http.server 8080 ) &
    echo "✔  serveur HTTP démo sur :8080  (/srv/www)"
fi

# ── Bannière ───────────────────────────────────────────────
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

# ── sshd au premier plan ──────────────────────────────────
exec /usr/sbin/sshd -D -e

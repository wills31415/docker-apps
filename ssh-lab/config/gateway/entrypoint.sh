#!/usr/bin/env bash
# ============================================================
#  Entrypoint — GATEWAY (v5)
# ============================================================
set -euo pipefail

NODE_INDEX="${NODE_INDEX:-?}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# ── 1. Initialisation de /etc/ssh (volume nommé) ─────────────
mkdir -p /etc/ssh /var/run/sshd

cat > /etc/ssh/sshd_config << SSHD_CONF
Port 22
AddressFamily any
ListenAddress 0.0.0.0

PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication yes
PermitEmptyPasswords no

StrictModes no
UseDNS no
PrintMotd no

SyslogFacility AUTH
LogLevel ${LOG_LEVEL}

Subsystem sftp /usr/lib/openssh/sftp-server
SSHD_CONF

ssh-keygen -A 2>/dev/null
echo "✔  /etc/ssh initialisé (LogLevel=${LOG_LEVEL})"

# ── 2. Initialisation de /root/.ssh ──────────────────────────
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f /root/.ssh/config ]; then
    cat > /root/.ssh/config << 'SSHCONF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 30
    ServerAliveCountMax 3
SSHCONF
    chmod 600 /root/.ssh/config
fi

# ── 3. Injection clé admin (root + admin, idempotente) ───────
ADMIN_PUBKEY="/admin-key/id_admin.pub"
for AUTH_KEYS in "/root/.ssh/authorized_keys" "/home/admin/.ssh/authorized_keys"; do
    if [ -f "$ADMIN_PUBKEY" ]; then
        PUBKEY_CONTENT="$(cat "$ADMIN_PUBKEY")"
        touch "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
        grep -qF "$PUBKEY_CONTENT" "$AUTH_KEYS" 2>/dev/null \
            || echo "$PUBKEY_CONTENT" >> "$AUTH_KEYS"
    fi
done
chown admin:admin /home/admin/.ssh/authorized_keys 2>/dev/null || true
[ -f "$ADMIN_PUBKEY" ] && echo "✔  Clé admin injectée (root + admin)"

# ── 4. Mots de passe ─────────────────────────────────────────
[ -n "${ROOT_PASSWORD:-}"  ] && echo "root:${ROOT_PASSWORD}"  | chpasswd
[ -n "${ADMIN_PASSWORD:-}" ] && echo "admin:${ADMIN_PASSWORD}" | chpasswd

# ── 5. Bannière ───────────────────────────────────────────────
echo ""
echo "┌──────────────────────────────────────────────────┐"
printf "│  🌐  GATEWAY-%-2s démarré                           │\n" "$NODE_INDEX"
echo "│  Réseaux : client-net + server-net               │"
printf "│  sshd    : foreground  │  LogLevel : %-9s  │\n" "$LOG_LEVEL"
echo "│  Utilisateurs : root, admin (sudo NOPASSWD)      │"
echo "└──────────────────────────────────────────────────┘"
echo ""
echo "── sshd logs ────────────────────────────────────────"
echo ""

# ── 6. sshd en foreground ────────────────────────────────────
exec /usr/sbin/sshd -D -e

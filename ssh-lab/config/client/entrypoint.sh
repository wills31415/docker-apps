#!/usr/bin/env bash
# ============================================================
#  Entrypoint — CLIENT (v5)
# ============================================================
set -euo pipefail

NODE_INDEX="${NODE_INDEX:-?}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# ── 1. Initialisation de /root/.ssh ──────────────────────────
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

# ── 2. Injection clé admin dans root (idempotente) ───────────
ADMIN_PUBKEY="/admin-key/id_admin.pub"
for AUTH_KEYS in "/root/.ssh/authorized_keys" "/home/admin/.ssh/authorized_keys"; do
    if [ -f "$ADMIN_PUBKEY" ]; then
        PUBKEY_CONTENT="$(cat "$ADMIN_PUBKEY")"
        touch "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
        if ! grep -qF "$PUBKEY_CONTENT" "$AUTH_KEYS" 2>/dev/null; then
            echo "$PUBKEY_CONTENT" >> "$AUTH_KEYS"
        fi
    fi
done
# S'assurer que admin possède bien son authorized_keys
chown admin:admin /home/admin/.ssh/authorized_keys 2>/dev/null || true
[ -f "$ADMIN_PUBKEY" ] && echo "✔  Clé admin injectée (root + admin)"

# ── 3. Mots de passe ─────────────────────────────────────────
[ -n "${ROOT_PASSWORD:-}"  ] && echo "root:${ROOT_PASSWORD}"  | chpasswd 2>/dev/null || true
[ -n "${ADMIN_PASSWORD:-}" ] && echo "admin:${ADMIN_PASSWORD}" | chpasswd 2>/dev/null || true

# ── 4. Bannière ───────────────────────────────────────────────
echo ""
echo "┌──────────────────────────────────────────────────┐"
printf "│  🖥️  CLIENT-%-2s démarré                            │\n" "$NODE_INDEX"
echo "│  Réseau : client-net  │  sshd : non             │"
echo "│  Utilisateurs : root, admin (sudo NOPASSWD)      │"
echo "│  Paquets : ssh, sudo, nano, make, tar, awk, sed  │"
echo "└──────────────────────────────────────────────────┘"
echo ""

# ── 5. Processus principal ────────────────────────────────────
exec sleep infinity

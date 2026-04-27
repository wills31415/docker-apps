#!/usr/bin/env bash
# ============================================================
#  Entrypoint — MASTER (v5)
# ============================================================
set -euo pipefail

NODE_INDEX="${NODE_INDEX:-1}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
N_CLIENTS="${N_CLIENTS:-0}"
N_GATEWAYS="${N_GATEWAYS:-0}"
N_SERVERS="${N_SERVERS:-0}"

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

# 2a. Copie de la clé admin privée depuis le bind-mount
ADMIN_PRIVKEY_SRC="/admin-key/id_admin"
ADMIN_PRIVKEY_DST="/root/.ssh/id_admin"
ADMIN_PUBKEY_SRC="/admin-key/id_admin.pub"
ADMIN_PUBKEY_DST="/root/.ssh/id_admin.pub"

if [ -f "$ADMIN_PRIVKEY_SRC" ]; then
    cp "$ADMIN_PRIVKEY_SRC" "$ADMIN_PRIVKEY_DST"
    chmod 600 "$ADMIN_PRIVKEY_DST"
    cp "$ADMIN_PUBKEY_SRC"  "$ADMIN_PUBKEY_DST"
    chmod 644 "$ADMIN_PUBKEY_DST"
    echo "✔  Clé admin copiée → /root/.ssh/id_admin"
else
    echo "❌  Clé admin introuvable : $ADMIN_PRIVKEY_SRC"
fi

# 2b. SSH config (toujours régénéré pour refléter la topologie)
cat > /root/.ssh/config << SSHCONF
Host *
    User root
    IdentityFile /root/.ssh/id_admin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ConnectTimeout 5

SSHCONF
for i in $(seq 1 "$N_CLIENTS");  do printf "Host client-%s\n    Hostname client-%s\n\n"  "$i" "$i" >> /root/.ssh/config; done
for i in $(seq 1 "$N_GATEWAYS"); do printf "Host gateway-%s\n    Hostname gateway-%s\n\n" "$i" "$i" >> /root/.ssh/config; done
for i in $(seq 1 "$N_SERVERS");  do printf "Host server-%s\n    Hostname server-%s\n\n"   "$i" "$i" >> /root/.ssh/config; done
chmod 600 /root/.ssh/config
echo "✔  /root/.ssh/config généré (${N_CLIENTS}C + ${N_GATEWAYS}G + ${N_SERVERS}S)"

# 2c. Autocomplétion bash pour lab-exec (toujours régénérée)
BASHRC="/root/.bashrc"
[ -f "$BASHRC" ] && sed -i '/# >>> lab-exec completion >>>/,/# <<< lab-exec completion <<</d' "$BASHRC"

LAB_NODES="all clients gateways servers"
for i in $(seq 1 "$N_CLIENTS");  do LAB_NODES="$LAB_NODES client-$i";  done
for i in $(seq 1 "$N_GATEWAYS"); do LAB_NODES="$LAB_NODES gateway-$i"; done
for i in $(seq 1 "$N_SERVERS");  do LAB_NODES="$LAB_NODES server-$i";  done

cat >> "$BASHRC" << BASH_COMPLETION
# >>> lab-exec completion >>>
__lab_exec_complete() {
    local cur="\${COMP_WORDS[COMP_CWORD]}"
    case "\$COMP_CWORD" in
        1) COMPREPLY=( \$(compgen -W "${LAB_NODES}" -- "\$cur") ) ;;
        *) COMPREPLY=() ;;
    esac
}
complete -F __lab_exec_complete lab-exec
# <<< lab-exec completion <<<
BASH_COMPLETION
echo "✔  Autocomplétion lab-exec écrite dans /root/.bashrc"

# ── 3. Injection clé admin (root + admin, idempotente) ───────
for AUTH_KEYS in "/root/.ssh/authorized_keys" "/home/admin/.ssh/authorized_keys"; do
    if [ -f "$ADMIN_PUBKEY_DST" ]; then
        PUBKEY_CONTENT="$(cat "$ADMIN_PUBKEY_DST")"
        touch "$AUTH_KEYS"
        chmod 600 "$AUTH_KEYS"
        grep -qF "$PUBKEY_CONTENT" "$AUTH_KEYS" 2>/dev/null \
            || echo "$PUBKEY_CONTENT" >> "$AUTH_KEYS"
    fi
done
chown admin:admin /home/admin/.ssh/authorized_keys 2>/dev/null || true
echo "✔  Clé admin injectée (root + admin)"

# ── 4. Mots de passe ─────────────────────────────────────────
[ -n "${ROOT_PASSWORD:-}"  ] && echo "root:${ROOT_PASSWORD}"  | chpasswd
[ -n "${ADMIN_PASSWORD:-}" ] && echo "admin:${ADMIN_PASSWORD}" | chpasswd

# ── 5. Bannière ───────────────────────────────────────────────
echo ""
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  👑  MASTER démarré — nœud d'administration SSH          │"
echo "│  Réseaux   : client-net + server-net (accès total)      │"
printf "│  sshd      : foreground  │  LogLevel : %-15s │\n" "$LOG_LEVEL"
echo "│  Utilisateurs : root, admin (sudo NOPASSWD)              │"
echo "│  Clé admin : /root/.ssh/id_admin  (ed25519)             │"
printf "│  Nœuds : %d client(s) │ %d gateway(s) │ %d server(s)          │\n" \
    "$N_CLIENTS" "$N_GATEWAYS" "$N_SERVERS"
echo "│  lab-exec <TAB>  ← autocomplétion active               │"
echo "└──────────────────────────────────────────────────────────┘"
echo ""
echo "── sshd logs ─────────────────────────────────────────────"
echo ""

# ── 6. sshd en foreground ────────────────────────────────────
exec /usr/sbin/sshd -D -e

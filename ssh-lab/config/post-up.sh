#!/usr/bin/env bash
# ============================================================
#  post-up.sh — Résumé affiché après un démarrage réussi
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cluster.conf
source "$SCRIPT_DIR/cluster.conf"

ADMIN_PUBKEY="$SCRIPT_DIR/../shared/admin-key/id_admin.pub"
KEY_FP=""
[ -f "$ADMIN_PUBKEY" ] && KEY_FP="$(ssh-keygen -l -f "$ADMIN_PUBKEY" 2>/dev/null | awk '{print $2}')"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ssh-lab — Cluster démarré ✅                      ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  MASTER   : 1 (ssh-master)  ← admin SSH sur tous les nœuds   ║\n"
printf "║  CLIENTs  : %-3d │ GATEWAYs : %-3d │ SERVERs : %-3d             ║\n" \
    "$N_CLIENTS" "$N_GATEWAYS" "$N_SERVERS"
printf "║  LogLevel : %-10s                                       ║\n" "$LOG_LEVEL"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Utilisateurs sur CHAQUE nœud                                 ║"
echo "║    root   — mot de passe : ROOT_PASSWORD                      ║"
echo "║    admin  — mot de passe : ADMIN_PASSWORD  (sudo NOPASSWD)   ║"
echo "║  Paquets  : ssh, sudo, nano, make, tar, awk, sed, bash        ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Clé SSH admin (master → tous les nœuds)                      ║"
printf "║    Empreinte : %-49s ║\n" "$KEY_FP"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Accès SSH depuis l'hôte → GATEWAYs                          ║"
for i in $(seq 1 "$N_GATEWAYS"); do
    hp=$(( SSH_PORT_BASE + i ))
    printf "║    ssh root@localhost -p %-5d   # → gateway-%-2d              ║\n" "$hp" "$i"
done
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  cluster-exec.sh  [groupe] <commande>  ← depuis l'hôte       ║"
echo "║    ./cluster-exec.sh all     \"hostname\"                       ║"
echo "║    ./cluster-exec.sh servers \"df -h /\"                       ║"
echo "║    ./cluster-exec.sh server-1 \"id\"                           ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  upload.sh  [groupe] <fichier>  ← depuis l'hôte              ║"
echo "║    ./upload.sh all     deploy.tar.gz                          ║"
echo "║    ./upload.sh servers app.tar.gz                             ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  lab-exec  [groupe] <commande>  ← depuis le master           ║"
echo "║    docker exec -it ssh-master bash                            ║"
echo "║    lab-exec all     \"hostname\"                               ║"
echo "║    lab-exec servers \"apk add curl\"                           ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Autocomplétion (si pas encore activée)                      ║"
echo "║    source ~/docker-apps/ssh-lab/completions.bash              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

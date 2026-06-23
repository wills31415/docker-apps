#!/usr/bin/env bash
# ============================================================
#  box-apply.sh — « Appliquer » de l'IHM de la box.
#
#  Valide config/box.conf, le pousse vers la box, et recharge
#  À CHAUD la DMZ + les redirections de ports (iptables).
#
#  Les changements STRUCTURELS (IP publique, sous-réseaux, baux)
#  ne sont PAS rechargeables à chaud → un avertissement invite
#  à faire « da restart net-lab ».
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/config/box.conf"
APPLIED="$SCRIPT_DIR/shared/box/box.conf"
BOX="net-lab-box"

[ -f "$CFG" ] || { echo "❌  introuvable : $CFG"; exit 1; }

# ── Validation du format des redirections ─────────────────────
# shellcheck source=config/box.conf
source "$CFG"
errors=0
for rule in "${FORWARDS[@]:-}"; do
    [ -z "$rule" ] && continue
    IFS=':' read -r proto pub tgt tport <<< "$rule"
    if [ -z "$proto" ] || [ -z "$pub" ] || [ -z "$tgt" ] || [ -z "$tport" ]; then
        echo "❌  redirection mal formée (proto:port:cible:port) : '$rule'"; errors=1; continue
    fi
    case "$proto" in tcp|udp) ;; *) echo "❌  proto invalide ('$proto') : '$rule'"; errors=1 ;; esac
    [[ "$pub"   =~ ^[0-9]+$ ]] || { echo "❌  port public non numérique : '$rule'"; errors=1; }
    [[ "$tport" =~ ^[0-9]+$ ]] || { echo "❌  port cible non numérique : '$rule'"; errors=1; }
done
[ "$errors" -eq 0 ] || { echo "   → corrige config/box.conf puis relance."; exit 1; }

# ── Détection de dérive structurelle vs la config appliquée ───
_val()    { ( set +eu; source "$1" >/dev/null 2>&1; printf '%s' "${!2-}" ); }
_leases() { ( set +eu; source "$1" >/dev/null 2>&1; printf '%s\n' "${LEASES[@]:-}" ); }
if [ -f "$APPLIED" ]; then
    drift=0
    for v in PUBLIC_IP WAN_SUBNET LAN_SUBNET DMZ_SUBNET; do
        [ "$(_val "$CFG" "$v")" = "$(_val "$APPLIED" "$v")" ] || drift=1
    done
    [ "$(_leases "$CFG")" = "$(_leases "$APPLIED")" ] || drift=1
    if [ "$drift" -eq 1 ]; then
        echo "⚠️  Changement STRUCTUREL détecté (IP publique / sous-réseaux / baux)."
        echo "    Le hot-reload n'applique que DMZ + redirections."
        echo "    Pour appliquer le reste :  da restart net-lab"
        echo ""
    fi
fi

# ── La box tourne-t-elle ? ────────────────────────────────────
if [ "$(docker inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null)" != "true" ]; then
    echo "❌  La box ($BOX) n'est pas démarrée. Lance : da up net-lab"
    exit 1
fi

# ── Pousse la config + applique ───────────────────────────────
mkdir -p "$(dirname "$APPLIED")"
cp "$CFG" "$APPLIED"           # bind-monté ro dans la box → visible instantanément
echo "📡  Application de la config sur la box…"
docker exec "$BOX" box apply
echo ""
echo "💡  Vérifier : ./box-status.sh"

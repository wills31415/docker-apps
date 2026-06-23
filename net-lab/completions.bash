#!/usr/bin/env bash
# ============================================================
#  net-lab — Autocomplétion Bash (côté hôte)
#
#  À sourcer une fois dans ~/.bashrc :
#    echo 'source ~/docker-apps/net-lab/completions.bash' >> ~/.bashrc
#    source ~/docker-apps/net-lab/completions.bash
#
#  Complète :
#    ./cluster-exec.sh <TAB>  → groupes + machines (hors box)
#    ./upload.sh       <TAB>  → groupes d'upload
#  Les machines (server-1, client-2…) sont déduites de
#  config/topology.conf.
# ============================================================

_SSHLAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_netlab_nodes() {
    local conf="$_SSHLAB_DIR/config/topology.conf"
    local ns=0 nc=0
    if [ -f "$conf" ]; then
        ns="$(grep -E '^N_SERVERS=' "$conf" | tail -1 | cut -d= -f2 | tr -dc '0-9')"
        nc="$(grep -E '^N_CLIENTS=' "$conf" | tail -1 | cut -d= -f2 | tr -dc '0-9')"
    fi
    local out="all gateway servers clients nas"
    local i
    for i in $(seq 1 "${ns:-0}"); do out="$out server-$i"; done
    for i in $(seq 1 "${nc:-0}"); do out="$out client-$i"; done
    echo "$out"
}

_netlab_cluster_exec() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$(_netlab_nodes)" -- "$cur") )
    fi
}

_netlab_upload() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "all gateway servers clients nas" -- "$cur") )
    else
        COMPREPLY=( $(compgen -f -- "$cur") )
    fi
}

complete -F _netlab_cluster_exec cluster-exec.sh ./cluster-exec.sh
complete -F _netlab_upload upload.sh ./upload.sh

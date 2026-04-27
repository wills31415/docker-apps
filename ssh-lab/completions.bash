#!/usr/bin/env bash
# ============================================================
#  ssh-lab — Autocomplétion Bash (côté hôte)
#
#  À sourcer UNE FOIS dans votre ~/.bashrc :
#
#    echo 'source ~/docker-apps/ssh-lab/completions.bash' >> ~/.bashrc
#    source ~/docker-apps/ssh-lab/completions.bash
#
#  Ce fichier active la complétion pour :
#    - ./cluster-exec.sh  <TAB>  → groupes et nœuds disponibles
#    - ./upload.sh        <TAB>  → groupes disponibles
#
#  Les nœuds individuels (client-1, server-2…) sont générés
#  dynamiquement depuis config/cluster.conf.
# ============================================================

# Répertoire de ce fichier = racine de ssh-lab/
_SSHLAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers internes ──────────────────────────────────────────

# Retourne la liste des groupes + nœuds individuels depuis cluster.conf
__sshlab_all_targets() {
    local conf="$_SSHLAB_DIR/config/cluster.conf"
    local targets="all master clients gateways servers"

    if [ -f "$conf" ]; then
        # Sous-shell isolé pour ne pas polluer l'environnement courant
        local n_clients n_gateways n_servers
        n_clients=$(  bash -c "source '$conf' 2>/dev/null; echo \${N_CLIENTS:-0}" )
        n_gateways=$( bash -c "source '$conf' 2>/dev/null; echo \${N_GATEWAYS:-0}" )
        n_servers=$(  bash -c "source '$conf' 2>/dev/null; echo \${N_SERVERS:-0}" )

        local i
        for i in $(seq 1 "$n_clients");  do targets="$targets client-$i";  done
        for i in $(seq 1 "$n_gateways"); do targets="$targets gateway-$i"; done
        for i in $(seq 1 "$n_servers");  do targets="$targets server-$i";  done
    fi

    echo "$targets"
}

# Retourne les groupes valides pour upload (pas de nœuds individuels)
__sshlab_upload_targets() {
    echo "all master clients gateways servers"
}

# ── Complétion de cluster-exec.sh ────────────────────────────
#
#  Argument 1 → groupe ou nœud    (complétion dynamique)
#  Argument 2+ → commande bash    (pas de complétion — texte libre)
#
__sshlab_exec_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]:-}"

    case "$COMP_CWORD" in
        1)
            # Premier argument : groupe ou nœud
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "$(__sshlab_all_targets)" -- "$cur") )
            ;;
        *)
            # Arguments suivants : commande bash — pas de complétion automatique
            # (laisser bash utiliser sa complétion de commandes par défaut)
            COMPREPLY=()
            ;;
    esac
}

# ── Complétion de upload.sh ───────────────────────────────────
#
#  Argument 1 → groupe              (complétion : all|master|clients|…)
#  Argument 2 → chemin du fichier   (complétion : fichiers locaux)
#
__sshlab_upload_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    case "$COMP_CWORD" in
        1)
            # Premier argument : groupe cible
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "$(__sshlab_upload_targets)" -- "$cur") )
            ;;
        2)
            # Deuxième argument : fichier à uploader — complétion de fichiers
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

# ── Enregistrement des complétions ───────────────────────────
#
# On enregistre pour les chemins absolus et relatifs les plus courants.
# L'utilisateur peut ajouter d'autres alias selon son organisation.
#
complete -F __sshlab_exec_complete   "$_SSHLAB_DIR/cluster-exec.sh"
complete -F __sshlab_upload_complete "$_SSHLAB_DIR/upload.sh"

# Support des invocations avec chemin relatif depuis ssh-lab/
# (ex: depuis ~/docker-apps/, on ferait ssh-lab/cluster-exec.sh)
complete -F __sshlab_exec_complete   "cluster-exec.sh"
complete -F __sshlab_upload_complete "upload.sh"

# ── Complétion de uploads-clear.sh ───────────────────────────
#
#  Argument 1 → groupe  (all | all-dir | master | clients | gateways | servers)
#  Pas de 2e argument.
#
__sshlab_clear_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    case "$COMP_CWORD" in
        1) COMPREPLY=( $(compgen -W "all all-dir master clients gateways servers" -- "$cur") ) ;;
        *) COMPREPLY=() ;;
    esac
}

# ── Complétion de volumes-rm.sh ──────────────────────────────
#
#  Argument 1 → groupe ou nœud (mêmes cibles que cluster-exec,
#               sans "all-dir" qui est spécifique à uploads-clear)
#
__sshlab_volumes_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    case "$COMP_CWORD" in
        1) COMPREPLY=( $(compgen -W "$(__sshlab_all_targets)" -- "$cur") ) ;;
        *) COMPREPLY=() ;;
    esac
}

complete -F __sshlab_clear_complete   "$_SSHLAB_DIR/uploads-clear.sh"
complete -F __sshlab_volumes_complete "$_SSHLAB_DIR/volumes-rm.sh"

# Support invocations avec chemin relatif
complete -F __sshlab_clear_complete   "uploads-clear.sh"
complete -F __sshlab_volumes_complete "volumes-rm.sh"

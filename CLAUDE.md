# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Gestionnaire de clusters Docker personnalisés piloté par la méta-commande shell `da` (Docker Apps). Chaque sous-répertoire (sauf ceux préfixés `.` ou `old.`) est un cluster autonome.

## Commandes courantes

```bash
# Gestion des clusters (commande "da" disponible après: source .bash_utils)
da up <cluster>             # Démarre un cluster (crée .lock)
da down <cluster>           # Arrête un cluster (supprime .lock)
da restart <cluster>        # down + up
da build <cluster>          # Build les images custom
da logs <cluster>           # Logs (--follow --tail=50 par défaut)
da status                   # Vue d'ensemble de tous les clusters

# Rebuild complet
da restart <cluster> --build

# ssh-lab spécifique
da restart ssh-lab --build  # Après modif Dockerfile/entrypoint
# Seul cluster.conf doit être édité — docker-compose.yaml est auto-généré par pre-up.sh
```

## Architecture

```
docker-apps/
├── .bash_utils          ← Fonction "da" + autocomplétion (sourcé dans .bashrc)
├── <cluster>/
│   ├── config/
│   │   ├── docker-compose.yaml   ← Obligatoire
│   │   ├── pre-up.sh             ← Hook optionnel (avant compose up)
│   │   ├── post-up.sh            ← Hook optionnel (après compose up)
│   │   ├── pre-down.sh           ← Hook optionnel (avant compose down)
│   │   ├── post-down.sh          ← Hook optionnel (après compose down)
│   │   └── <service>/Dockerfile  ← Image custom
│   ├── shared/                   ← Bind mounts accessibles depuis l'hôte
│   └── .lock                     ← Présent = cluster actif
```

## Conventions critiques

- **Volumes** : tous les bind mounts hôte doivent pointer vers `<cluster>/shared/`. Depuis un `docker-compose.yaml` dans `config/`, le chemin relatif est `../shared/`.
- **Hooks** : doivent être `chmod +x`. S'ils échouent (exit != 0), l'opération `up`/`down` est interrompue.
- **ssh-lab** : le `docker-compose.yaml` est **auto-généré** par `pre-up.sh` depuis `cluster.conf`. Ne jamais l'éditer à la main.
- **Gitignore** : `/*/shared/*` — les données runtime ne sont jamais committées.

## Clusters existants

| Cluster | Description | Particularités |
|---------|-------------|----------------|
| `postgresql` | PostgreSQL 16 + Adminer | Healthcheck, initdb scripts, réseau isolé |
| `ssh-lab` | Lab SSH multi-noeud (master/client/gateway/server) | Compose auto-généré, topologie configurable via `cluster.conf` |
| `sftp` | Serveur SFTP (atmoz/sftp) | Minimal, port 2222 |

## Ajouter un nouveau cluster

1. `mkdir -p <nom>/config <nom>/shared`
2. Créer `<nom>/config/docker-compose.yaml`
3. (Optionnel) Ajouter des hooks `pre-up.sh`, `post-up.sh`, etc.
4. Vérifier avec `da status`

## Remote

- GitHub : `wills31415/docker-apps`
- Branche principale : `main`

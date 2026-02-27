# Docker Apps Manager — `da`

Gestionnaire de petits clusters Docker personnalisés, piloté depuis le shell via la méta-commande `da`.  
La configuration est sourcée depuis `docker-apps/.bash_utils` dans votre `.bashrc`.

---

## Table des matières

1. [Structure des répertoires](#1-structure-des-répertoires)
2. [Mécanisme de lock](#2-mécanisme-de-lock)
3. [Scripts hooks optionnels](#3-scripts-hooks-optionnels)
4. [Configuration globale](#4-configuration-globale)
5. [Référence des commandes `da`](#5-référence-des-commandes-da)
6. [Autocomplétion Bash](#6-autocomplétion-bash)
7. [Ajouter un nouveau cluster](#7-ajouter-un-nouveau-cluster)
8. [Ajouter un service avec image custom](#8-ajouter-un-service-avec-image-custom)

---

## 1. Structure des répertoires

```
docker-apps/
├── .bash_utils                   ← Sourcé dans .bashrc
│
├── cluster-A/
│   ├── .lock                     ← Créé au démarrage, supprimé à l'arrêt
│   ├── config/
│   │   ├── docker-compose.yaml   ← OBLIGATOIRE
│   │   ├── pre-up.sh             ← Optionnel
│   │   ├── post-up.sh            ← Optionnel
│   │   ├── pre-down.sh           ← Optionnel
│   │   ├── post-down.sh          ← Optionnel
│   │   └── service-name/
│   │       ├── Dockerfile        ← Image custom pour 'service-name'
│   │       └── ...               ← Toutes les ressources de build
│   └── shared/
│       └── ...                   ← Volumes montés accessibles depuis l'hôte
│
└── cluster-B/
    ├── config/
    │   └── docker-compose.yaml
    └── shared/
```

> **Règle fondamentale sur les volumes :** Tous les volumes du `docker-compose.yaml` destinés à être accessibles depuis la machine hôte **doivent** être montés sous `docker-apps/cluster-name/shared/`. Cela garantit un emplacement prévisible et cohérent pour toutes les données persistantes.

---

## 2. Mécanisme de lock

À chaque démarrage d'un cluster, un fichier `docker-apps/cluster-name/.lock` est créé. Il est supprimé à l'arrêt.

**Contenu du fichier `.lock` :**
```
PID=24567
STARTED_AT=2025-08-08 14:23:45
```

| Champ        | Description                                               |
|--------------|-----------------------------------------------------------|
| `PID`        | PID du processus shell qui a lancé `da up`                |
| `STARTED_AT` | Horodatage du démarrage au format `YYYY-MM-DD HH:MM:SS`   |

**Points importants :**
- Ce mécanisme est **indépendant** de l'existence ou non des scripts hooks optionnels.
- Il sert uniquement à refléter l'état logique du cluster du point de vue du gestionnaire `da`. Il ne vérifie pas l'état réel des containers Docker.
- Si un `.lock` est présent, `da up` refusera de redémarrer le cluster. Utiliser `da restart` ou supprimer manuellement le `.lock` si nécessaire.
- Si un `.lock` est absent lors d'un `da down`, l'arrêt est tenté quand même avec un avertissement.

---

## 3. Scripts hooks optionnels

Quatre scripts Bash peuvent être placés dans `config/` pour exécuter des actions avant/après le montage et le démontage du cluster.

| Fichier        | Moment d'exécution                                          |
|----------------|-------------------------------------------------------------|
| `pre-up.sh`    | Avant `docker compose up` — préparer des ressources, vérifier des prérequis |
| `post-up.sh`   | Après `docker compose up` — initialiser des données, notifier |
| `pre-down.sh`  | Avant `docker compose down` — sauvegarder des données, prévenir des dépendants |
| `post-down.sh` | Après `docker compose down` — nettoyer des ressources temporaires |

**Comportement :**
- Si le script est **absent** → aucune action, le déroulement continue normalement.
- Si le script est **présent mais non exécutable** → avertissement affiché, le script est ignoré.
- Si le script **échoue** (code de retour non nul) → l'opération `up` ou `down` est interrompue.

**Rendre un script exécutable :**
```bash
chmod +x docker-apps/cluster-name/config/pre-up.sh
```

**Exemple de `pre-up.sh` :**
```bash
#!/usr/bin/env bash
# Crée les répertoires nécessaires dans shared/ avant le démarrage
mkdir -p "$(dirname "$0")/../shared/data"
mkdir -p "$(dirname "$0")/../shared/logs"
```

---

## 4. Configuration globale

Ces variables sont définies en haut de `.bash_utils` et peuvent être surchargées avant de sourcer le fichier.

| Variable                          | Valeur par défaut    | Description                                   |
|-----------------------------------|----------------------|-----------------------------------------------|
| `CUSTOM_DOCKER_CLUSTER_BASE_PATH` | Répertoire de `.bash_utils` | Chemin racine de `docker-apps/`          |
| `DOCKER_COMPOSE_UP_DEFAULT_OPTS`  | `(-d)`               | Options par défaut passées à `docker compose up` |
| `DOCKER_COMPOSE_DOWN_DEFAULT_OPTS`| `(-t 0)`             | Options par défaut passées à `docker compose down` |
| `DOCKER_COMPOSE_LOGS_DEFAULT_OPTS`| `(--follow --tail=50)` | Options par défaut passées à `docker compose logs` |

**Surcharger les options par défaut (exemple dans `.bashrc`) :**
```bash
DOCKER_COMPOSE_DOWN_DEFAULT_OPTS=(-t 30)   # Laisser 30s aux containers pour s'arrêter
source ~/docker-apps/.bash_utils
```

---

## 5. Référence des commandes `da`

### `da up <cluster> [options...]`
Monte un cluster. Crée le fichier `.lock` après un démarrage réussi.

```bash
da up postgresql
da up postgresql --build          # Rebuild les images avant de démarrer
da up postgresql --scale app=3   # Démarrer 3 instances du service 'app'
```

Déroulement : `pre-up.sh` → `docker compose up` → création du `.lock` → `post-up.sh`

---

### `da down <cluster> [options...]`
Démonte un cluster. Supprime le fichier `.lock` après un arrêt réussi.

```bash
da down postgresql
da down postgresql -t 30          # Laisser 30s aux containers (surcharge le défaut)
da down postgresql --volumes      # Supprimer également les volumes
```

Déroulement : `pre-down.sh` → `docker compose down` → suppression du `.lock` → `post-down.sh`

---

### `da restart <cluster> [options-up...]`
Enchaîne un `da down` puis un `da up`. Les options supplémentaires sont passées au `up`.

```bash
da restart postgresql
da restart postgresql --build
```

---

### `da build <cluster> [options...]`
Construit ou reconstruit les images custom du cluster.

```bash
da build postgresql
da build postgresql --no-cache    # Forcer un rebuild complet sans cache
da build postgresql service-name  # Rebuilder uniquement un service spécifique
```

---

### `da logs <cluster> [options...]`
Affiche les logs du cluster. Par défaut : `--follow --tail=50`.

```bash
da logs postgresql
da logs postgresql --tail=200     # Afficher les 200 dernières lignes
da logs postgresql --no-follow    # Afficher sans suivre en temps réel
da logs postgresql service-name   # Logs d'un seul service
```

---

### `da status`
Affiche le statut de tous les clusters détectés dans `docker-apps/`. Pour les clusters actifs, les détails du `.lock` sont affichés.

```
📊 Statut des clusters Docker
══════════════════════════════
  🟢 postgresql — Actif
     ├ STARTED_AT : 2025-08-08 14:23:45
     └ PID        : 24567
  🔴 redis — Arrêté
  🔴 monitoring — Arrêté ⚠️  (docker-compose.yaml manquant)
```

---

### `da help`
Affiche l'aide intégrée avec la liste des commandes et des clusters disponibles.

---

## 6. Autocomplétion Bash

L'autocomplétion est activée automatiquement au sourçage de `.bash_utils`.

| Frappe                    | Résultat                                                   |
|---------------------------|------------------------------------------------------------|
| `da <TAB>`                | Liste toutes les sous-commandes disponibles                |
| `da up <TAB>`             | Liste tous les clusters disponibles                        |
| `da down <TAB>`           | Liste tous les clusters disponibles                        |
| `da restart <TAB>`        | Liste tous les clusters disponibles                        |
| `da build <TAB>`          | Liste tous les clusters disponibles                        |
| `da logs <TAB>`           | Liste tous les clusters disponibles                        |
| `da status <TAB>`         | Aucune complétion (pas d'argument attendu)                 |
| `da help <TAB>`           | Aucune complétion (pas d'argument attendu)                 |

---

## 7. Ajouter un nouveau cluster

Voici la marche à suivre complète pour ajouter un nouveau cluster `mon-cluster`.

### Étape 1 — Créer la structure de répertoires

```bash
mkdir -p docker-apps/mon-cluster/config
mkdir -p docker-apps/mon-cluster/shared
```

### Étape 2 — Créer le `docker-compose.yaml`

```bash
touch docker-apps/mon-cluster/config/docker-compose.yaml
```

Exemple minimal :
```yaml
services:
  app:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ../shared/html:/usr/share/nginx/html:ro
```

> **Important :** Les chemins de volumes relatifs dans `docker-compose.yaml` sont relatifs au répertoire du fichier compose, soit `config/`. Pour pointer vers `shared/`, utiliser `../shared/`.

### Étape 3 — (Optionnel) Ajouter des scripts hooks

```bash
touch docker-apps/mon-cluster/config/pre-up.sh
chmod +x docker-apps/mon-cluster/config/pre-up.sh
```

### Étape 4 — Vérifier que le cluster est détecté

```bash
da status
# ou
da help
```

Le nouveau cluster doit apparaître dans la liste.

### Étape 5 — Démarrer le cluster

```bash
da up mon-cluster
```

---

## 8. Ajouter un service avec image custom

Pour un service `worker` dans le cluster `mon-cluster` nécessitant un Dockerfile custom :

### Étape 1 — Créer le répertoire du service

```bash
mkdir -p docker-apps/mon-cluster/config/worker
```

### Étape 2 — Créer le Dockerfile et les ressources associées

```
docker-apps/mon-cluster/config/worker/
├── Dockerfile
├── entrypoint.sh
└── ...                  ← Toutes les ressources nécessaires au build
```

### Étape 3 — Référencer le build dans `docker-compose.yaml`

```yaml
services:
  worker:
    build:
      context: ./worker       # Relatif à config/, pointe vers config/worker/
      dockerfile: Dockerfile
    volumes:
      - ../shared/output:/app/output
```

### Étape 4 — Construire l'image

```bash
da build mon-cluster
```

Les builds ultérieurs peuvent être forcés sans cache :
```bash
da build mon-cluster --no-cache
```

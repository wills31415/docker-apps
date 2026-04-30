# SYNC.md — Workflow `sync-pack`

Synchroniser le modpack en une commande : **édition GUI dans Modrinth App → upload Modrinth → resync serveur**.

> Source de vérité : la **Modrinth App locale** (le profil dans `~/.local/share/ModrinthApp/profiles/...`).
> Cible : le projet Modrinth (unlisted) + le cluster Docker `minecraft-server`.

## Workflow quotidien

```bash
cd ~/docker-apps/minecraft-server

# Édite le pack dans la Modrinth App (ajout / suppression / MAJ de mod)
# Puis :
./sync-pack.sh "ajout du mod XYZ"
```

Ce que fait le script :
1. Détecte le profil ModrinthApp local (basé sur `PACK_NAME`).
2. Pour chaque `.jar` du dossier `mods/` du profil : SHA-1 → API Modrinth → URL canonique + métadonnées env.
3. Mods absents de Modrinth → embarqués dans `overrides/mods/` du `.mrpack` (pas d'auto-update).
4. Configs du profil → embarquées dans `overrides/config/`.
5. Upload de la nouvelle version sur Modrinth.
6. `da restart minecraft-server` → itzg détecte la nouvelle version (via `MODRINTH_FORCE_SYNCHRONIZE=true`) et resynchronise les mods.
7. Les joueurs voient une notif "Update available" dans leur Modrinth App.

## Setup one-time (étapes humaines)

### H1 — Créer le projet Modpack sur Modrinth
- https://modrinth.com/dashboard/projects → *New project*
- Type : **Modpack** | Visibilité : **Unlisted**
- Récupérer le **Project ID** (menu ⋮ → Copy ID).

### H2 — Générer un PAT (Personal Access Token)
- https://modrinth.com/settings/account → *Personal Access Tokens*
- Scopes : `Create versions`, `Modify versions`, `Read projects`.
- Stocker (au choix) :

  ```bash
  # Option A : secret-tool (KWallet/libsecret) — recommandé sous Kubuntu
  secret-tool store --label="Modrinth PAT" service modrinth-pat user "$USER"
  # (saisir le PAT au prompt)

  # Option B : fichier protégé
  install -m 600 -D /dev/stdin ~/.config/sync-pack/token <<< "ton-PAT-ici"
  ```

### H3 — Configurer le script
Éditer la tête de `sync-pack.sh` (ou exporter en env) :

```bash
PACK_NAME="pack"                  # Nom exact du dossier de profil dans ~/.local/share/ModrinthApp/profiles/
PACK_DISPLAY_NAME="coupaing-craft" # Nom utilisé dans le manifest .mrpack uploadé
MODRINTH_PROJECT_ID="<copié à l'étape H1>"
GAME_VERSION="1.21.11"
LOADER_VERSION="0.19.2"
```

### H4 — Importer le pack dans la Modrinth App locale (après le 1er upload)
- Ouvrir le lien Modrinth dans la Modrinth App → *Install*.
- L'App suit ce pack et notifie des futures versions.
- Idem sur les postes des joueurs (transmettre le lien).

## Validation par paliers

```bash
# Palier A — Build local seul (pas d'upload, pas de deploy)
./sync-pack.sh --dry-run "test palier A"
unzip -p dry-run-pack.mrpack modrinth.index.json | jq

# Palier B — Upload sans deploy (vérifier que la version apparaît sur Modrinth)
./sync-pack.sh --no-deploy "première version"

# Palier C — Cycle complet
./sync-pack.sh "test cycle complet"
da logs minecraft-server   # surveiller "Modpack downloaded", "Synchronizing mods"
```

## Mods server-only

Les mods listés dans `SERVER_ONLY_PROJECTS` (par défaut : `c2me-fabric,krypton,dynmap`) sont taggés `{client: unsupported, server: required}` dans le manifest, peu importe ce que dit Modrinth. Ils ne sont **pas** téléchargés par les clients.

Pour ajouter un mod à cette liste :
```bash
SERVER_ONLY_PROJECTS="c2me-fabric,krypton,dynmap,nouveau-slug" ./sync-pack.sh "msg"
```
Ou éditer la valeur par défaut en tête de `sync-pack.sh`.

## Pièges à l'ajout d'un mod

Avant d'ajouter un mod au profil master, vérifier :

1. **Version Minecraft strict** : un mod tagué pour `1.21.10` peut refuser de charger sur `1.21.11` (ex: `accessorify 2.4.0-beta.5` → `{depends minecraft @ [1.21.10]}` strict). Faire `curl 'https://api.modrinth.com/v2/project/<slug>/version?loaders=["fabric"]&game_versions=["1.21.11"]'` et vérifier qu'au moins une version sort. Pas de filet : Modrinth ne refuse pas l'install au build.

2. **Hard deps client-only** : certains mods déclarent `modmenu` en dépendance `required` (ex: `underground-village,-stoneholm`). ModMenu est `client:required, server:unsupported` → côté serveur, Fabric Loader refuse de charger le mod. Soit downgrade vers une version sans cette dep (Stoneholm 1.5.2 sur 1.20.1 n'avait pas ce hard dep), soit retirer le mod.

3. **Java version** : versions alpha de C2ME (`0.3.7+alpha.0.x`) exigent Java 22+ (`{depends java @ [>=22]}`). L'image `itzg/minecraft-server:stable-java21` est figée sur Java 21 — utiliser le track `release` (`0.3.6.0.0` au moment de l'écriture).

4. **Fabric loader compat** : certains mods exigent un loader 0.16+ ou un fabric-api récent. Vérifier dans `dependencies` du fichier de version Modrinth.

## Mods incompatibles serveur

Si un mod déclaré `server: required` sur Modrinth plante en réalité côté serveur (souvent un mod client-only mal taggé), l'ajouter à `MODRINTH_EXCLUDE_FILES` dans `config/.env` :

```env
MODRINTH_EXCLUDE_FILES=...,nom-du-fichier-jar-fautif*
```

⚠️ **Toujours vérifier le client/serveur split avant d'exclure**. Depuis MC 1.21.2 les recettes vivent côté serveur → `jei` / `rei` / `emi` doivent être présents côté serveur (cf. `CLAUDE.md` §"Règles mods").

## Mods non-Modrinth

Si tu poses un `.jar` dans `mods/` du profil qui n'existe pas sur Modrinth (mod custom, dev preview, version retirée…), le script le détecte automatiquement et l'embarque dans `overrides/mods/` du `.mrpack`. Conséquence : il sera distribué aux joueurs **mais perd l'auto-update**.

## Troubleshooting

| Symptôme | Cause probable | Action |
|---|---|---|
| `❌ Aucun profil ModrinthApp trouvé` | `PACK_NAME` ne correspond à aucun dossier | Vérifier le listing affiché par le script ; ajuster `PACK_NAME` ou utiliser `MODRINTH_PROFILE_DIR=...` |
| `❌ PAT Modrinth introuvable` | Token pas stocké | Refaire H2 |
| `❌ MODRINTH_PROJECT_ID manquant` | Variable vide | Renseigner dans le script ou en env |
| HTTP 400 à l'upload | `version_number` doublon (2 syncs dans la même minute) | Attendre 1 min ou exporter `VERSION_NUMBER=...-2` |
| HTTP 401 | PAT invalide / révoqué | Régénérer le PAT (H2) |
| HTTP 403 | PAT sans le scope `Create versions` | Régénérer avec les bons scopes |
| HTTP 429 | Rate limit (300 req/min) | Attendre 1 min |
| `❌ Doublons de mods` | Deux versions du même project_id dans `mods/` du profil | Supprimer la version obsolète dans la Modrinth App |
| Le serveur ne resynchronise pas | `MODRINTH_FORCE_SYNCHRONIZE` absent du `.env` | Vérifier `config/.env` (cf. § migration) |

## Migration `.env` (à faire après approbation Modrinth)

Tant que le projet Modrinth `coupaing-craft` est en **Under review** (modération initiale, ~24-72h après création), itzg ne peut pas le résoudre via slug : la version uploadée existe mais l'API publique répond 404. On reste donc en mode `.mrpack` local : `MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack`.

Une fois le projet **Approved** sur Modrinth, basculer en mode "slug + auto-sync" :

```diff
-MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack
+MODRINTH_MODPACK=coupaing-craft
+MODRINTH_VERSION_TYPE=release
 MODRINTH_FORCE_SYNCHRONIZE=true
 MODRINTH_PROJECTS=
```

`MODRINTH_FORCE_SYNCHRONIZE=true` et `MODRINTH_PROJECTS=` (vide) sont déjà actifs depuis la migration "profil master" — les 6 mods server-only sont inclus directement dans le pack.

Rollback : remettre `MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack` ; le fichier reste dans `shared/data/`.

## Fichiers générés (gitignored)

- `dry-run-pack.mrpack` (mode `--dry-run`)
- `last-pack.mrpack` (mode `--no-upload`)

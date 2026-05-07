# SYNC.md — Workflow `sync-pack`

Synchroniser le modpack en une commande : **édition GUI dans Modrinth App → upload Modrinth → resync serveur**.

> Source de vérité : la **Modrinth App locale** (profil `~/.local/share/ModrinthApp/profiles/CoupaingCraft-Master/`).
> Cible : le projet Modrinth (unlisted, ID `4fBwVYft`) + le cluster Docker `minecraft-server`.

## Workflow quotidien

```bash
cd ~/docker-apps/minecraft-server

# 1. Édite le pack dans la Modrinth App (profil CoupaingCraft-Master) :
#    ajout / suppression / MAJ de mod ou resource pack.
# 2. Si une update upstream casse un patch maison, le ré-appliquer :
#    ./patches/<patch-name>/apply.sh ~/.local/share/ModrinthApp/profiles/CoupaingCraft-Master/mods/<jar>
# 3. Sync :
./sync-pack.sh "ajout du mod XYZ"
```

Ce que fait le script :

1. Détecte le profil ModrinthApp local (par défaut `CoupaingCraft-Master`).
2. Pour chaque asset du profil (`mods/*.jar`, `resourcepacks/*.zip`, `shaderpacks/*.zip`) : SHA-1 → API Modrinth → URL canonique + métadonnées env.
3. Assets absents de Modrinth (jars patchés, contenu custom) → embarqués dans `overrides/<dossier>/` du `.mrpack`.
4. Si un dossier `<profile>/pack-overrides/` existe, son contenu est embarqué tel quel dans `overrides/` (cf. `CLAUDE.md` § Configs custom à shipper). **Les configs `<profile>/config/` du master ne sont PAS embarquées** par défaut, pour éviter d'écraser les tweaks joueurs aux updates.
5. Auto-distribution locale du `.mrpack` :
   - `shared/data/coupaing-craft-initial.mrpack` — fallback consommé par itzg.
   - `shared/data/dynmap/web/coupaing-craft.mrpack` — URL stable pour `update-client.sh`.
6. Upload de la nouvelle version sur Modrinth.
7. `da restart minecraft-server` → itzg détecte la nouvelle version (`MODRINTH_FORCE_SYNCHRONIZE=true`) et resynchronise.
8. Les joueurs voient une notif "Update available" dans leur Modrinth App **une fois Modrinth approuvé**. En attendant : utiliser `update-client.sh` côté joueur (cf. `CLAUDE.md` § Distribution clients).

## État Modrinth

Le projet `coupaing-craft` est encore **Under review** — l'API publique répond `404` :

```bash
curl -sw "%{http_code}\n" -o /dev/null https://api.modrinth.com/v2/project/coupaing-craft
# 404 = encore en review (ou rejected)
# 200 = approved ; passer à la § Migration .env ci-dessous
```

Conséquences :
- itzg ne peut pas résoudre `MODRINTH_MODPACK=coupaing-craft` → fallback sur fichier local `MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack`.
- Les ModrinthApp clients ne peuvent pas charger la page projet (crash JS `null project_type`) → distribution manuelle des jars.
- Pas de notif "Update available".
- L'auth + l'écriture (POST `/v2/version`) marchent quand même → `sync-pack.sh` upload bien, on peut juste pas pull.

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
Éditer la tête de `sync-pack.sh` (ou exporter en env). Valeurs actuelles par défaut :

```bash
PACK_NAME="CoupaingCraft-Master"      # Dossier de profil dans ~/.local/share/ModrinthApp/profiles/
PACK_DISPLAY_NAME="coupaing-craft"    # Nom dans le manifest .mrpack (= slug Modrinth)
MODRINTH_PROJECT_ID="4fBwVYft"
GAME_VERSION="1.21.11"                # Fallback : le script lit VERSION= depuis config/.env au runtime (= 1.20.1 actuellement)
LOADER_VERSION="0.19.2"
```

### H4 — Importer le pack dans la Modrinth App locale (après approbation)
- Ouvrir le lien Modrinth dans la Modrinth App → *Install* → ce profil sera nommé `CoupaingCraft` (≠ master).
- L'App suit ce pack et notifie des futures versions.
- Idem sur les postes des joueurs (transmettre le lien).

⚠️ **Garder `CoupaingCraft-Master` unlinked du pack** — c'est le profil source de vérité, qui contient les mods server-only en plus. Ne **jamais** le relinker, sinon le filtre client de l'App retire les server-only.

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

Liste actuelle des mods server-only embarqués dans le pack (master profile) : `c2me-fabric`, `krypton`, `dynmap`, `universal-graves`, `configmanager`, `maxhealthfix`. Les 3 derniers sont déjà tagués `unsupported` côté Modrinth, pas besoin du forçage.

## Mods client-required (forçage opposé)

Certains mods déclarent `client: unsupported` sur Modrinth alors qu'ils sont **en réalité requis côté client** — typiquement les mods de worldgen qui registent des items dans le registry partagé (kick au join sinon), ou les addons Create avec des items propres.

Liste forcée `{client: required, server: required}` via `CLIENT_REQUIRED_PROJECTS` (défaut) :

```
lithostitched, create-peaceful, harvest-enchantment, create_oxidized, create-pattern-schematics
```

À étendre si un nouveau mod kick les clients au join avec un mismatch de registry :

```bash
CLIENT_REQUIRED_PROJECTS="lithostitched,...,nouveau-slug" ./sync-pack.sh "msg"
```

## Patches binaires

Si un mod upstream a un bug non fixé qu'on patche localement (cf. `patches/`) :

1. Le `.jar` patché vit dans `mods/` du master profile, son SHA-1 ne matche plus Modrinth.
2. `sync-pack.sh` le détecte (`⚠️ Pas sur Modrinth → overrides/`) et l'embarque dans `overrides/mods/` du `.mrpack`.
3. Côté client, ModrinthApp extrait l'overrides → les joueurs ont le jar patché.
4. **À ré-appliquer** après chaque update upstream du mod concerné — sinon la nouvelle version (non patchée) écraserait le patch :

   ```bash
   ./patches/<nom>/apply.sh ~/.local/share/ModrinthApp/profiles/CoupaingCraft-Master/mods/<jar>
   ./sync-pack.sh "re-patch après update <mod>"
   ```

Voir `patches/<nom>/README.md` pour le détail de chaque patch.

## Pièges à l'ajout d'un mod

Avant d'ajouter un mod au profil master, vérifier :

1. **Version Minecraft strict** : un mod tagué pour `1.20.0` peut refuser de charger sur `1.20.1` (rare en 1.20.1 mais classique en 1.21.x avec les sous-versions strictes). Tester :

   ```bash
   curl -sG 'https://api.modrinth.com/v2/project/<slug>/version' \
     --data-urlencode 'loaders=["fabric"]' \
     --data-urlencode 'game_versions=["1.20.1"]' \
     | jq 'length'
   # 0 = pas de version compat → ne pas ajouter
   ```

2. **Hard deps client-only** : certains mods déclarent `modmenu` en dépendance `required` (ex: `underground-village,-stoneholm` ≥ 1.5.7). ModMenu est `client:required, server:unsupported` → côté serveur, Fabric Loader refuse de charger le mod. Soit downgrade vers une version sans cette dep (Stoneholm `1.5.5` sur 1.20.1 n'a pas ce hard dep), soit retirer le mod.

3. **Java version** : versions alpha de C2ME (`0.3.7+alpha.0.x`) exigent Java 22+. L'image `itzg/minecraft-server:stable-java21` est figée sur Java 21 — utiliser le track stable (`0.3.6.0.0` au moment de l'écriture).

4. **Fabric loader compat** : certains mods exigent un loader 0.16+ ou un `fabric-api` récent. Vérifier `dependencies` du fichier de version Modrinth.

5. **Ecosystème Create** : le pack utilise **Create-Fabric `0.5.1-j-build.1631`** (legacy fork pour 1.20.1 avec écosystème complet d'addons). Ne pas passer sur la branche `6.0.x` (modern fork) — incompatible avec la plupart des addons (`Enchantment Industry` notamment).

## Mods incompatibles serveur

Si un mod déclaré `server: required` sur Modrinth plante en réalité côté serveur (souvent un mod client-only mal taggé), l'ajouter à `MODRINTH_EXCLUDE_FILES` dans `config/.env` :

```env
MODRINTH_EXCLUDE_FILES=...,nom-du-fichier-jar-fautif*
```

⚠️ **Toujours vérifier le client/serveur split avant d'exclure**. Le piège classique en 1.21.2+ : les recettes vivent côté serveur → `jei` / `rei` / `emi` doivent être présents côté serveur (pas applicable en 1.20.1 où on est, mais bon à savoir pour une migration future).

## Mods non-Modrinth

Si tu poses un `.jar` dans `mods/` du master profile qui n'existe pas sur Modrinth (mod custom, dev preview, version retirée, jar patché localement), le script le détecte automatiquement et l'embarque dans `overrides/mods/` du `.mrpack`. Conséquence : il sera distribué aux joueurs **mais perd l'auto-update**.

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
| Le serveur ne resynchronise pas après sync | (Devrait pas arriver — `sync-pack.sh` copie auto le .mrpack vers `shared/data/coupaing-craft-initial.mrpack`.) | Vérifier le timestamp du fichier ; relancer `da restart minecraft-server` |
| Crash client `ArithmeticException: / by zero` au render Sophisticated | Patch `sophisticatedcore-mathhelper-div0` perdu après update | Ré-appliquer le patch (cf. § Patches binaires) puis sync |

## Migration `.env` (à faire après approbation Modrinth)

Tant que le projet Modrinth est en **Under review**, on reste en mode `.mrpack` local : `MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack`.

Une fois le projet **Approved** (HTTP 200 sur l'API publique), basculer en mode "slug + auto-sync" :

```diff
-MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack
+MODRINTH_MODPACK=coupaing-craft
+MODRINTH_VERSION_TYPE=release
```

`MODRINTH_FORCE_SYNCHRONIZE=true` et `MODRINTH_PROJECTS=` (vide) sont **déjà actifs** — les server-only sont embarqués dans le pack via le profil master.

Rollback : remettre `MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack` ; le fichier reste dans `shared/data/`.

Une fois la migration faite, `sync-pack.sh` reprend son cycle complet : l'étape `da restart` resynchronisera depuis Modrinth (plus besoin de copier `last-pack.mrpack` à la main).

## Fichiers générés (gitignored)

- `dry-run-pack.mrpack` (mode `--dry-run`)
- `last-pack.mrpack` (mode `--no-upload`, ou à copier manuellement vers `shared/data/coupaing-craft-initial.mrpack` tant que Modrinth est Under review)

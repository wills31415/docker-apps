# CLAUDE.md — Modpack `coupaing-craft`

Toute session Claude dans `minecraft-server/` est centrée sur la **maintenance et la gestion du modpack CoupaingCraft**. La mécanique commune des clusters `da` (start/stop, hooks, etc.) vit dans le `CLAUDE.md` racine.

## Stack actuelle

| | |
|---|---|
| Minecraft | **1.20.1** (Fabric loader **0.19.2**) |
| Modpack | `coupaing-craft` (Modrinth, Project ID `4fBwVYft`, **Unlisted**) |
| Source de vérité | profil ModrinthApp local **`CoupaingCraft-Master`** |
| Image | `itzg/minecraft-server:stable-java21` (Java 21) |
| Pipeline d'édition | `./sync-pack.sh` (cf. [`SYNC.md`](./SYNC.md)) |
| Carte web | Dynmap mod, port hôte `25566` (8123 dans le container) |

⚠️ La version Minecraft a été migrée de `1.21.11` → `1.20.1` pour bénéficier de l'écosystème complet **Create-Fabric 0.5.1-j** + addons. La valeur par défaut `GAME_VERSION:=1.21.11` dans `sync-pack.sh` n'est qu'un fallback : le script lit `VERSION=` du `.env` à l'exécution.

## État Modrinth

Le projet est encore **Under review** (l'API publique répond `404` sur `/v2/project/coupaing-craft`). Tant que l'approbation n'est pas reçue :

- Le serveur charge le pack via fallback local : `MODRINTH_MODPACK=/data/coupaing-craft-initial.mrpack`.
- `sync-pack.sh` upload bien sur Modrinth (l'auth + l'écriture marchent même en review), mais ne **met pas à jour** le `.mrpack` local automatiquement → après un sync, copier manuellement `last-pack.mrpack` vers `shared/data/coupaing-craft-initial.mrpack` si on veut que le serveur prenne les nouveaux mods (le script déclenche `da restart` mais lit l'ancien fichier sans cette copie).
- Les ModrinthApp clients (joueurs distants) ne reçoivent pas la notif "Update available" → distribution manuelle des jars (cf. § Distribution manuelle aux joueurs).

Migration vers le mode "slug + auto-sync" (`MODRINTH_MODPACK=coupaing-craft` + `MODRINTH_VERSION_TYPE=release`) documentée dans [`SYNC.md`](./SYNC.md), à faire dès l'approbation reçue.

## Profils ModrinthApp

Deux profils sur la machine locale (Kubuntu) :

| Profil | Path | Rôle |
|---|---|---|
| `CoupaingCraft-Master` | `~/.local/share/ModrinthApp/profiles/CoupaingCraft-Master/` | Source de vérité, **unlinked** du pack Modrinth. Contient les mods server-only (`{client: unsupported}`) en plus des mods client. **Seul profil édité** — `sync-pack.sh` lit ses jars + configs. |
| `CoupaingCraft` | `~/.local/share/ModrinthApp/profiles/CoupaingCraft/` | Profil "joueur" — installé via le pack Modrinth (filtre auto les server-only). Sert à tester comme un client. **Ne pas éditer** (sera écrasé à chaque update du pack). |

⚠️ **Ne jamais relinker `CoupaingCraft-Master` au pack** — le filtre client de l'App retirerait les server-only et casserait la prochaine sync.

## Patches

Le dossier [`patches/`](./patches/) contient des patchs binaires sur les mods upstream non fixés en amont. Chaque sous-dossier a un `apply.sh` idempotent + un `README.md` explicatif.

À ré-appliquer **après chaque update upstream** du mod concerné, depuis le profil master :

```bash
./patches/sophisticatedcore-mathhelper-div0/apply.sh \
  ~/.local/share/ModrinthApp/profiles/CoupaingCraft-Master/mods/sophisticatedcore-*.jar
```

Le jar patché part automatiquement dans `overrides/` du `.mrpack` (son SHA-1 ne matche plus celui de Modrinth) → préservé à chaque cycle `sync-pack`.

### Patches actifs

| Patch | Cible | Symptôme fixé |
|---|---|---|
| [`sophisticatedcore-mathhelper-div0`](./patches/sophisticatedcore-mathhelper-div0/) | `sophisticatedcore-1.20.1-*.jar` | `ArithmeticException: / by zero` au render d'un BackpackScreen / StorageScreen — guard `a==0` ajouté |

## Distribution clients (Modrinth Under review)

Tant que l'auto-sync Modrinth ne marche pas, `sync-pack.sh` distribue automatiquement le `.mrpack` à deux endroits :

- `shared/data/coupaing-craft-initial.mrpack` — fallback local consommé par itzg au boot du serveur.
- `shared/data/dynmap/web/coupaing-craft.mrpack` — exposé via Dynmap HTTP (`http://<ip>:25566/coupaing-craft.mrpack`) → URL stable pour les clients.

### Sur un client (mode auto via script)

`update-client.sh` télécharge la dernière version depuis l'URL Dynmap, calcule le diff avec le profil local, et touche **uniquement** `mods/`, `resourcepacks/`, `shaderpacks/`, `datapacks/`. Configs, options, journeymap data et autres préservées.

Le script lui-même est exposé via Dynmap HTTP (auto-copié à chaque `sync-pack.sh`) — pas besoin de cloner le repo côté client :

```bash
# Une fois (download + run) :
curl -fsSL http://90.79.99.178:25566/update-client.sh | bash

# Ou pour le garder localement et le relancer à volonté :
curl -fsSL http://90.79.99.178:25566/update-client.sh -o ~/update-client.sh
chmod +x ~/update-client.sh
~/update-client.sh
```

Le script auto-détecte le profil ModrinthApp standard `CoupaingCraft` (Flatpak SteamDeck, Linux natif, Windows). Override via :

```bash
~/update-client.sh /chemin/vers/profil                                  # path explicite
PACK_NAME=AutreProfil ~/update-client.sh                                # autre nom de profil
PACK_URL=http://autre.host:25566/coupaing-craft.mrpack ~/update-client.sh
```

Anciens fichiers déplacés dans `<profil>/.update-backup/<timestamp>/`, jamais supprimés.

### Sur un client (manuel, individuel)

Pour exposer un fichier précis (jar custom, asset isolé), le copier dans `shared/data/dynmap/web/` puis fournir l'URL au joueur. Procédure-type :

```bash
cp <chemin-vers-jar> /home/wsl/docker-apps/minecraft-server/shared/data/dynmap/web/
# Téléchargeable : http://<ip-publique>:25566/<nom-fichier>.jar
```

## Configs custom à shipper (`pack-overrides/`)

`sync-pack.sh` n'embarque **plus** automatiquement `<profile>/config/` du master profile dans le `.mrpack` (cause : ModrinthApp ré-extrait `overrides/config/` à chaque update → écrasement des tweaks joueur). YOSBR est inclus pour protéger `options.txt` & co. mais **pas les configs de mods**.

Pour shipper des defaults pack-spécifiques (ex: presets dynmap-public, JEI bookmarks pré-configurés), créer un dossier `<profile>/pack-overrides/` dans le master ; son contenu est embarqué tel quel dans `overrides/` du `.mrpack`. Ne **jamais** y mettre de configs susceptibles d'être tweakées par le joueur.

**Datapacks worldgen** : pour shipper un datapack qui doit s'appliquer à tous les serveurs/clients (ex: tweaks de spacing/separation des structures), placer le dossier dans `<profile>/pack-overrides/world/datapacks/<nom>/`. Il sera extrait par itzg dans `/data/world/datapacks/<nom>/` au boot et auto-chargé par MC. Exemple actif : `coupaing-craft-density` (boost villages + ATi structures, voir `pack-overrides/world/datapacks/coupaing-craft-density/`).

## Fichiers clés

```
minecraft-server/
├── CLAUDE.md                         ← ce fichier
├── SYNC.md                           ← workflow sync-pack détaillé
├── sync-pack.sh                      ← édition GUI → upload Modrinth → da restart + auto-dist local
├── update-client.sh                  ← update du profil ModrinthApp d'un client (SteamDeck) sans toucher aux configs
├── MODRINTH_BODY.md                  ← description Modrinth (à coller manuellement sur le dashboard)
├── MODS_VS_FABULOUSLY_OPTIMIZED.md   ← rapport de comparaison FO/CoupaingCraft (régénérable)
├── dry-run-pack.mrpack               ← --dry-run output (gitignored)
├── last-pack.mrpack                  ← copie auto du dernier pack généré (gitignored)
├── patches/                          ← patchs binaires (versionnés)
│   └── <patch-name>/
│       ├── apply.sh
│       ├── README.md
│       └── *.java                    ← sources des classes patchées
├── config/
│   ├── .env                          ← VERSION, mods, RCON, Dynmap, OPS
│   ├── docker-compose.yaml           ← services + ports + bind ../shared/data:/data
│   ├── pre-up.sh / post-up.sh        ← hooks lifecycle (lance le watcher Dynmap)
│   ├── pre-down.sh                   ← arrête le watcher (PID dans shared/)
│   ├── dynmap-auto-render.sh         ← daemon force-render autour des joueurs posés
│   └── dynmap-grave-marker.sh        ← (DÉSACTIVÉ en 1.20.1, voir post-up.sh)
└── shared/                           ← bind mount, gitignored
    ├── data/                         ← /data du container (monde, mods, config Dynmap, .mrpack local)
    ├── backups/                      ← snapshots manuels du monde
    └── dynmap-auto-render.{pid,log}  ← lifecycle géré par les hooks
```

## Configs personnelles (`.env.local`)

Pour garder des valeurs perso non-versionnées (pseudo OP, mot de passe RCON custom, etc.) sans pourrir le `.env` template :

```bash
# config/.env.local — gitignored, lu après .env, écrase ses valeurs.
OPS=TonPseudoMinecraft
RCON_PASSWORD=mon-secret-fort
```

Lu automatiquement par :
- `docker-compose.yaml` (deuxième `env_file`, `required: false`)
- `post-up.sh` (boucle `.env` puis `.env.local`)

`sync-pack.sh` ne lit que `.env` (pour `VERSION` / `FABRIC_LOADER_VERSION`) — c'est intentionnel : la version Minecraft n'a pas vocation à être perso.

## RCON

```bash
# Console interactive
docker exec -it minecraft_server rcon-cli

# Commande unique
docker exec minecraft_server rcon-cli "<cmd>"
```

⚠️ **Toujours quoter** la commande complète, sinon les coordonnées négatives sont parsées comme des flags :

```bash
# KO : unknown shorthand flag
docker exec minecraft_server rcon-cli dynmap radiusrender world -23 23 256
# OK
docker exec minecraft_server rcon-cli "dynmap radiusrender world -23 23 256"
```

## Dynmap

### Mapping monde

| Dimension MC | Dossier monde | Map Dynmap |
|---|---|---|
| `minecraft:overworld` | `world` | `surface`, `flat`, `cave` |
| `minecraft:the_nether` | `DIM-1` | `nether` |
| `minecraft:the_end` | `DIM1` | `the_end` |

Mods Create ajoutent `create_dd_ponder` (dimension interne au système Ponder de Create: Dreams & Desires) — désactivée dans `worlds.txt` (inutile pour les joueurs).

### Limitations Fabric

- **Pas de `dynmap reload`** → modif `configuration.txt` / `worlds.txt` / `markers.yml` ⇒ `da restart`.
- **Triggers actifs** : `blockupdate` + `chunkgenerate` uniquement. **Pas de `chunkload`** → un joueur qui traverse des chunks pré-générés ne déclenche aucun rendu. Compensé par `dynmap-auto-render.sh`.

### Watcher `dynmap-auto-render`

Daemon bash (`config/dynmap-auto-render.sh`) lancé par `post-up.sh`, tué par `pre-down.sh` via `shared/dynmap-auto-render.pid`. Toutes les `POLL_INTERVAL=30s`, lit la position des joueurs via RCON, regroupe ceux qui sont posés (déplacement < `MOVEMENT_THRESHOLD=32` blocs), et déclenche `dynmap radiusrender` sur le centroïde (rayon `BASE_RADIUS=192 + (n-1)*PER_PLAYER_BONUS=64`, cooldown `300s` par grille `64`).

Tunables via env (export avant `da up`) : `POLL_INTERVAL`, `MOVEMENT_THRESHOLD`, `CLUSTER_DISTANCE`, `BASE_RADIUS`, `PER_PLAYER_BONUS`, `COOLDOWN_SEC`, `COOLDOWN_GRID`.

Logs : `tail -f shared/dynmap-auto-render.log`.

### Overrides UI web

Vivants dans `shared/data/dynmap/web/` (gitignored car `shared/`) :
- `index.html` patché : `<link>` vers `css/override.css` + JS qui replace la compass dans `.leaflet-top.leaflet-left`.
- `css/override.css` : tweaks tactiles (`@media (max-width: 900px)`).
- `update-webpath-files: false` dans `configuration.txt` → sinon Dynmap écrase nos overrides au démarrage.

À déplacer un jour vers `config/dynmap-web-overrides/` + copy hook pour les rendre versionnables.

## Wipe de monde (garder mods + configs)

```bash
da down minecraft-server
# Dans shared/data/, supprimer :
#   world/, world_nether/, world_the_end/,
#   usercache.json, ops.json, banned-*.json, whitelist.json,
#   logs/, crash-reports/.
# Garder :
#   mods/, config/, libraries/, *.mrpack, eula.txt
#   (server.properties sera regénéré).
da up minecraft-server
```

`REMOVE_OLD_MODS=true` ne touche que `mods/` (resync depuis le pack), pas le monde.

## Gotchas — modpack & maintenance

- **Patcher SophisticatedCore après chaque update upstream** — bug `intMaxCappedMultiply` div/0 non fixé en amont (Forge/NeoForge/Fabric). Trigger : items à `maxStackSize=0` (souvent générés par mods Polymer comme `moretools`) ou état NBT particulier d'un coffre.
- **Cohérence VERSION** : `.env` (`VERSION=1.20.1`) est la source. `sync-pack.sh` a un fallback statique à `1.21.11` mais lit `.env` au runtime — ne pas se fier au commentaire.
- **Mods retirés du pack disparaissent** au prochain `da restart` (`REMOVE_OLD_MODS=true`). `MODRINTH_EXCLUDE_FILES` est la seule barrière contre les mods client-only embarqués qui plantent côté serveur.
- **Vérifier client/serveur split avant d'exclure** un mod. Depuis MC 1.21.2 les recettes vivent côté serveur → `jei` / `rei` / `emi` doivent être présents côté serveur ; **ne pas** les mettre dans `MODRINTH_EXCLUDE_FILES`. (Note : on est en 1.20.1, mais le piège est documenté pour la prochaine migration.)
- **Polymer + Sophisticated** : items générés par Polymer (`moretools`, autres) peuvent avoir des propriétés exotiques qui font crasher Sophisticated. Le patch `sophisticatedcore-mathhelper-div0` couvre le cas div/0, mais d'autres incompats peuvent surgir.
- **Coords négatives en RCON** → quoter la commande complète.
- **Modrinth API 404 sur le projet** = encore en review. Pas de notif joueur, distribution manuelle obligatoire.
- **RCON port 25575** ne doit **jamais** être ouvert sur Internet (admin total).
- **Dynmap port 25566** n'a pas d'auth — soit reverse proxy, soit `webpassword-protected: true` dans `configuration.txt`.

## Pointeurs externes

- Workflow `sync-pack` détaillé, paliers de validation, troubleshooting upload : [`SYNC.md`](./SYNC.md)
- Mécanique commune `da` (lifecycle, hooks, conventions volumes) : `../CLAUDE.md`
- Patchs binaires détaillés : `patches/<nom>/README.md`

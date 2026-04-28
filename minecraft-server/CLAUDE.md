# CLAUDE.md — minecraft-server

Guide spécifique au cluster `minecraft-server`. Le `CLAUDE.md` racine couvre la mécanique commune des clusters `da`.

## Stack

- Image : `itzg/minecraft-server:latest`
- Type : `MODRINTH` (Fabric)
- Version : Minecraft `1.21.11`, Fabric loader `0.19.2`
- Modpack : `MODRINTH_MODPACK=/data/Base-1.21.11-1.0.0.mrpack` (`.mrpack` placé dans `shared/data/`)
- Mods perf ajoutés par-dessus le pack : `c2me-fabric`, `krypton`
- Carte web : Dynmap (mod) sur l'hôte `DYNMAP_PORT` (25566) → container 8123

## Ports

| Port hôte | Cible | Usage |
|---|---|---|
| `SERVER_PORT` (25565) | 25565 | Joueurs Minecraft |
| `RCON_PORT` (25575) | 25575 | RCON — **ne pas** ouvrir en NAT/PAT |
| `DYNMAP_PORT` (25566) | 8123 | Carte web — ouvrable en NAT/PAT, **pas d'auth par défaut** |

## Fichiers clés

```
minecraft-server/
├── config/
│   ├── .env                       ← TOUTE la config (mods, mémoire, gameplay, RCON, Dynmap)
│   ├── docker-compose.yaml        ← Services + ports + volume ../shared/data:/data
│   ├── pre-up.sh                  ← mkdir shared/{data,backups}
│   ├── post-up.sh                 ← Affiche infos + démarre le watcher Dynmap
│   ├── pre-down.sh                ← Tue le watcher Dynmap (PID dans shared/)
│   └── dynmap-auto-render.sh      ← Daemon de force-render autour des joueurs posés
└── shared/                        ← bind mount, gitignored
    ├── data/                      ← /data du container (monde, mods, configs)
    │   └── dynmap/                ← Config + tuiles + web overrides Dynmap
    ├── backups/
    ├── dynmap-auto-render.pid     ← PID du watcher (lifecycle géré par les hooks)
    └── dynmap-auto-render.log     ← Logs du watcher
```

## RCON

```bash
# Console interactive
docker exec -it minecraft_server rcon-cli

# Commande unique
docker exec minecraft_server rcon-cli <cmd>
```

Gotcha : les coordonnées négatives sont parsées comme des flags par `rcon-cli`. **Toujours quoter** la commande complète :

```bash
# KO : unknown shorthand flag
docker exec minecraft_server rcon-cli dynmap radiusrender world -23 23 256
# OK
docker exec minecraft_server rcon-cli "dynmap radiusrender world -23 23 256"
```

## Règles mods (MODRINTH)

- `REMOVE_OLD_MODS=true` → tout mod retiré de `MODRINTH_PROJECTS`/pack disparaît au prochain démarrage. `MODRINTH_EXCLUDE_FILES` est la seule barrière contre les mods client-only embarqués dans le pack.
- **Vérifier le client/serveur split AVANT d'exclure**. Depuis MC 1.21.2 les recettes vivent côté serveur → `jei` / `rei` / `emi` doivent être présents côté serveur. Ne pas les mettre dans `MODRINTH_EXCLUDE_FILES`.
- Les mods perf ajoutés (`c2me-fabric`, `krypton`) sont compatibles `VIEW_DISTANCE` élevé. Lithium et FerriteCore viennent du pack.
- Pour ajouter un mod : `MODRINTH_PROJECTS=...,nouveau-slug` puis `da restart minecraft-server`.

## Dynmap

### Config principale : `shared/data/dynmap/configuration.txt`

Réglages non-évidents posés cette session :
- `update-webpath-files: false` — sinon Dynmap écrase `web/` au démarrage et nos overrides UI sautent.
- `webpage-title: "Carte du serveur"`, `sidebaropened: pinned`, `hideifspectator: true`.
- `deftemplatesuffix: lowres` — évite le iso hires qui laissait des trous visibles.
- Throttling agressif (`tileupdatedelay: 1`, `save-pending-period: 60`, `tiles-rendered-at-once: 4`, `parallelrendercnt: 2`, `per-tick-time-limit: 80`, `maxchunkspertick: 400`, etc.).

### Limitations Dynmap-Fabric à connaître

- **Pas de commande `dynmap reload`** sur Fabric. Toute modif de `configuration.txt` / `worlds.txt` / `markers.yml` → `da restart minecraft-server`.
- **Triggers supportés** : `blockupdate` et `chunkgenerate` uniquement. **Pas de `chunkload`**. Conséquence : un joueur qui traverse des chunks déjà générés ne déclenche aucun rendu → trous sur la carte. C'est ce que compense le watcher.
- Vérifier les triggers actifs : `rcon-cli dynmap triggerstats`.

### Mapping monde ↔ Dynmap

| Dimension MC | Dossier monde | Map name dans Dynmap |
|---|---|---|
| `minecraft:overworld` | `world` | `surface` (et `flat`, `cave`) |
| `minecraft:the_nether` | `DIM-1` | `nether` |
| `minecraft:the_end` | `DIM1` | `the_end` |

Commandes utiles :
```bash
# Render forcé autour d'un point
rcon-cli "dynmap radiusrender world 100 -200 512"
# Stats / queue
rcon-cli "dynmap stats"
rcon-cli "dynmap purgequeue"
# Purge des tuiles d'une map (attention : pas de retour en arrière)
rcon-cli "dynmap purgemap world surface"
```

### Overrides UI web

Fichiers vivants dans `shared/data/dynmap/web/` (gitignored car `shared/`) :
- `index.html` — patché : `<link>` vers `css/override.css` activé + snippet JS qui déplace la compass dans `.leaflet-top.leaflet-left` pour qu'elle s'aligne avec les contrôles natifs.
- `css/override.css` — tweaks tactiles (`@media (max-width: 900px)` : 17px texte, 44px tap targets, hitbar 48px, etc.) + reset positionnel pour la compass déplacée.

Ces overrides ne sont **pas versionnés** (sont dans `shared/`). Une réorg pour les déplacer dans `config/dynmap-web-overrides/` + copy hook reste à faire (cf. mémoire conversation).

## Watcher dynmap-auto-render

`config/dynmap-auto-render.sh` — daemon bash lancé par `post-up.sh`, tué par `pre-down.sh` via `shared/dynmap-auto-render.pid`.

Logique : toutes les `POLL_INTERVAL=30s`, lit la position des joueurs via RCON, détecte ceux qui sont "posés" (déplacement < `MOVEMENT_THRESHOLD=32` blocs sur 2 polls consécutifs), les regroupe à `CLUSTER_DISTANCE=128`, et déclenche `dynmap radiusrender` au centroïde avec rayon `BASE_RADIUS=192 + (n-1)*PER_PLAYER_BONUS=64`. Cooldown 300s par zone (grille 64).

Tuner via env avant `da up` (ou export dans le shell qui lance le watcher) :
```
POLL_INTERVAL MOVEMENT_THRESHOLD CLUSTER_DISTANCE
BASE_RADIUS PER_PLAYER_BONUS
COOLDOWN_SEC COOLDOWN_GRID
```

Logs : `tail -f minecraft-server/shared/dynmap-auto-render.log`.

## Wipe de monde (garder mods + configs)

Procédure utilisée cette session pour repartir from scratch sans réinstaller les mods :

```bash
da down minecraft-server
# Depuis shared/data/, supprimer : world/, world_nether/, world_the_end/,
# usercache.json, ops.json, banned-*.json, whitelist.json, logs/, crash-reports/.
# Garder : mods/, config/, libraries/, *.mrpack, eula.txt, server.properties (sera regen).
da up minecraft-server
```

`REMOVE_OLD_MODS=true` ne touche que `mods/` (resync depuis le pack), pas le monde.

## Gotchas récap

- Coords négatives en RCON → quoter la commande complète.
- Modif config Dynmap → `da restart`, pas de `dynmap reload`.
- Mod ajouté à `MODRINTH_EXCLUDE_FILES` puis besoin de le réintroduire → ne pas oublier de retirer aussi de l'exclude.
- `shared/` est gitignored : tout ce qui doit survivre à un wipe de `shared/` (overrides web, configs custom) doit être trackable depuis `config/`.
- Le port 25575 (RCON) ne doit **jamais** être ouvert sur Internet — accès admin total au serveur.
- Le port 25566 (Dynmap) n'a pas d'auth — soit reverse proxy, soit `webpassword-protected: true` dans `configuration.txt` si on veut restreindre.

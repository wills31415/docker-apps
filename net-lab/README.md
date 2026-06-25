# net-lab — simulateur de réseau domestique (box + LAN + DMZ)

Lab Docker pédagogique qui simule un petit réseau type « box internet » :
un **routeur/box** qui fait du NAT, des redirections de ports et une DMZ, plus
des machines Linux réparties en quatre rôles. Idéal pour s'entraîner au
port-forwarding, aux jump hosts et à l'isolation réseau, sans matériel.

Piloté par la méta-commande `da` du Docker Apps Manager.

---

## Topologie

```
   client-1, client-2 ── WAN  203.0.113.0/24 ──┐   (IP "publiques", plage de doc RFC5737)
                          box = 203.0.113.2     │
                                            [ BOX ]  routeur NAT / pare-feu
                                              /       \
                         LAN 192.168.1.0/24          DMZ 192.168.2.0/24
                         (box = .1)                  (box = .1)
                          🚪 gateway 192.168.1.10      🗄️  nas 192.168.2.10  (seul)
                          🖥️  server-1 192.168.1.20
```

| Rôle | Réseau | Description |
|------|--------|-------------|
| **box** | wan + lan + dmz | Le routeur. NAT, redirections, DMZ. Ne s'administre que via son « IHM » (voir plus bas). |
| **gateway** | lan | « Entrée des artistes » : point d'entrée SSH du réseau domestique. |
| **server** (0..N) | lan | Machines du LAN domestique. |
| **nas** | dmz | Seul en DMZ, exposé par une redirection de port. |
| **client** (0..N) | wan | Machines « extérieures » (ex. wifi public) ; n'atteignent le réseau que via l'IP publique. |

### Politique de pare-feu de la box (la « vraie » DMZ)

| De \ Vers | WAN | LAN | DMZ |
|-----------|-----|-----|-----|
| **WAN** | — | redirections (DNAT) | redirection NAS (DNAT) |
| **LAN** | ✅ | — | ✅ |
| **DMZ** | ✅ | ❌ **bloqué** | — |

`LAN → DMZ` est autorisé, mais `DMZ → LAN` est bloqué : si le NAS (exposé sur
Internet) est compromis, l'attaquant ne peut pas rebondir vers le LAN.

---

## Démarrage

```bash
da up net-lab --build     # premier démarrage (build des images)
da up net-lab             # redémarrage rapide
da restart net-lab        # après modif de topology.conf ou des champs [STRUCTUREL] de box.conf
da restart net-lab --build# après modif d'un Dockerfile / entrypoint
da down net-lab
```

Auth : `root` / `ROOT_PASSWORD` (voir `config/topology.conf`) sur **chaque
machine** — jamais sur la box.

### Test depuis un client (l'acteur « extérieur »)

> Sur macOS, l'hôte ne route pas vers les réseaux Docker : on teste donc depuis
> un conteneur **client**, qui joue le rôle de la machine sur Internet.

```bash
docker exec -it net-lab-client-1 bash

ssh -p 2222 root@203.0.113.2          # → gateway (entrée des artistes)
ssh -p 2022 root@203.0.113.2          # → NAS (DMZ)
curl http://203.0.113.2:8080          # → service HTTP démo du NAS, via DNAT

# Jump host vers une machine du LAN (mot de passe demandé à chaque saut) :
ssh -J root@203.0.113.2:2222 root@192.168.1.20
```

### Boîte à outils réseau (sur les nodes)

Chaque machine embarque de quoi diagnostiquer : `ping`, `traceroute`, `mtr`,
`dig`/`nslookup`, `tcpdump`, `nc`, `iperf3` et `nmap`. Exemples parlants :

```bash
nmap 203.0.113.2                     # quels ports la box expose-t-elle ?
traceroute 203.0.113.2               # la box apparaît comme hop (2 hops si EGRESS_VIA_BOX=1)
tcpdump -ni any port 8080            # observer le trafic redirigé
```

---

## La box — son « IHM »

La box se configure **uniquement** via un fichier + un script, jamais par
`docker exec` ni `cluster-exec.sh` (comme une vraie box : tout passe par l'IHM).

- **`config/box.conf`** — la config (IP publique, **mode d'egress**, baux
  statiques, DMZ host, redirections de ports). C'est le fichier que tu édites.
- **`./box-apply.sh`** — « Appliquer » : valide, pousse la config et recharge
  **à chaud** la DMZ + les redirections (iptables). Les champs `[STRUCTUREL]`
  (IP publique, sous-réseaux, baux, `EGRESS_VIA_BOX`) demandent un `da restart`.
- **`./box-status.sh`** — « Ouvrir l'IHM » : état courant (config + règles +
  **compteurs** de paquets, pour *voir* le pare-feu au travail).
  `./box-status.sh conntrack` montre le NAT traduire en direct ; `--watch`
  rafraîchit en continu.

Exemple : ajouter une redirection `tcp:8443:server-1:443` dans `box.conf`, puis
`./box-apply.sh` → active immédiatement, sans couper le lab.

---

## Fichiers de configuration

| Fichier | Rôle |
|---------|------|
| `config/topology.conf` | « Le matériel » : `N_SERVERS`, `N_CLIENTS`, `ROOT_PASSWORD`, `LOG_LEVEL`. |
| `config/box.conf` | « L'IHM » : `PUBLIC_IP`, sous-réseaux, `LEASES`, `DMZ_HOST`, `FORWARDS`. |
| `config/docker-compose.yaml` | **Auto-généré** par `pre-up.sh`. Ne pas éditer. |

Les machines reçoivent une IP fixe : épinglée via `LEASES` (`"nom:ip"`), sinon
auto-assignée dans le sous-réseau de leur rôle.

---

## Outils côté hôte (sur les machines, jamais la box)

```bash
./cluster-exec.sh <groupe|machine> "<cmd>"   # exec parallèle (all|gateway|servers|clients|nas)
./upload.sh <groupe> <fichier>               # dépose un fichier dans /uploads (ro)
./uploads-clear.sh <groupe>                  # purge shared/uploads/<groupe>
./reprovision.sh <groupe|machine>            # re-déclenche le first-boot sur une machine vivante
./stop.sh / ./start.sh / ./reboot.sh         # soft cycle (temporaire — en attente de `da start/stop`)
./volumes-rm.sh                              # legacy : ramasse d'éventuels volumes netlab_ résiduels
source completions.bash                       # autocomplétion bash (groupes + machines)
```

## Persistance — sémantique VM

Les nodes **n'ont plus de volumes nommés**. Leur persistance vient du
*writable layer* du conteneur, que Docker préserve entre `docker compose stop`
et `start` mais détruit à `down`/`up` (= conteneurs recréés).

- **Reboot fidèle** (`./reboot.sh` = `stop` + `start`) : **tout** le filesystem
  du node survit — config dans `/etc`, users, `/home`, logs, paquets installés
  avec `apt install`, restructurations top-level (`rm /home && ln -s /users /home`
  survit aussi). C'est le comportement d'une vraie machine.
- **Fresh install** (`da restart net-lab` = `down` + `up`, ou `da up --build`) :
  conteneurs recréés depuis l'image, writable layer détruit, marker
  `/var/lib/net-lab/.provisioned` absent ⇒ phase 1 de l'entrypoint ré-exécutée.
- **Propager une modif de `topology.conf` sans tout wiper** :
  `./reprovision.sh <node|all>` régénère `shared/node/runtime.conf`
  (bind-monté en ro sur `/net-lab/runtime.conf`), supprime le marker, puis
  restart. La phase 1 re-source le fichier ⇒ vraie propagation des valeurs
  hot-tunables (`LOG_LEVEL`, `ROOT_PASSWORD`). Le reste du writable layer
  est préservé.

## Notes

- **Mode d'egress (`EGRESS_VIA_BOX` dans `box.conf`)** — qui est la passerelle ?
  - `0` (défaut) : les machines sortent **directement via Docker**. La box ne
    fait que le DNAT entrant + le routage inter-segments, qu'elle MASQUERADE →
    les cibles voient l'IP de la box, **pas la vraie source**.
  - `1` : la box devient la **passerelle par défaut** des nodes LAN/DMZ. Tout le
    trafic la traverse, la **vraie source est préservée** en interne, et le NAT
    ne se fait plus qu'en sortie WAN (comme un vrai routeur). Parfait pour tout
    observer en un point. `[STRUCTUREL]` → `da restart` pour basculer.
- **DMZ host** : `DMZ_HOST` reçoit **tout le trafic entrant non explicitement
  redirigé** (la fonction « DMZ host » d'une box grand public). Les `FORWARDS`
  explicites gardent la priorité ; laisser vide pour désactiver.
- **Résolution de noms** : Docker résout les noms **par réseau**. Les machines
  d'un même segment se résolvent par nom ; entre segments, on utilise l'IP.

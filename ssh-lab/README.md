# ssh-lab — Cluster Docker pour tests SSH (v4)

Cluster de conteneurs Alpine légères répartis en quatre rôles SSH
(**MASTER**, **CLIENT**, **GATEWAY**, **SERVER**),
géré via la méta-commande `da` du Docker Apps Manager.

---

## Nouveautés v4

| Point | Solution |
|---|---|
| SERVERs sans accès Internet | `internal: true` supprimé — isolation SSH purement **topologique** |
| Groupe en 1er argument (tous les outils) | `./cluster-exec.sh servers "cmd"` / `./upload.sh servers f.tgz` / `lab-exec servers "cmd"` |
| Autocomplétion côté hôte | `completions.bash` à sourcer dans `.bashrc` (nœuds dynamiques depuis `cluster.conf`) |
| Autocomplétion dans le master | Écrite dans `/root/.bashrc` par l'entrypoint à chaque démarrage |
| Volume uploads dédié au master | `shared/uploads/master/` → `/uploads/role/` dans le master |

---

## Isolation réseau des SERVERs — pourquoi retirer `internal: true`

La v3 utilisait `internal: true` sur `server-net`, ce qui bloquait **aussi** l'accès à Internet
depuis les SERVERs (impossible de faire `apk add` ou `curl`).

La v4 supprime `internal: true`. L'isolation SSH reste **garantie topologiquement** :

```
  client-1 ─── client-net                     (pas de route vers server-net)
  client-2 ─── client-net
                               gateway-1 ─── server-net ─── server-1, server-2, server-3
```

CLIENTs : uniquement sur `client-net`.
SERVERs : uniquement sur `server-net`.
Ces deux réseaux Docker n'ont **aucune interface commune** pour les nœuds non-gateway.
Docker ne crée aucune route entre des réseaux distincts.
→ **Il est impossible pour un CLIENT d'atteindre un SERVER directement.**
→ **Les SERVERs ont accès à Internet pour `apk add`, `curl`, etc.**

---

## Topologie réseau

```
  Machine hôte
  ┌────────────────────────────────────────────────────────────────┐
  │  ssh root@localhost -p 2221                  ┐                │
  │  ./cluster-exec.sh <groupe> <cmd>  (docker)  │                │
  │  ./upload.sh <groupe> <fichier>    (bind)     │                │
  └──────────────────────────────────────────────│────────────────┘
                                                  │
         ╔══════════════════════════════════════╗ │
         ║  client-net  (bridge)                ║ │
         ║  👑 MASTER ──────────────────────┐  ║ │
         ║  🖥️  client-1, client-2, …       │  ║ │
         ║                  🌐 gateway-1 ───╫───╫─┘
         ╚══════════════════╤═══════════════╝   │
                             │
         ╔══════════════════╧═══════════════╗
         ║  server-net  (bridge, internet ✅)║
         ║  👑 MASTER                        ║
         ║  🖧  server-1  ← apk add OK       ║
         ║  🖧  server-2  ← curl OK           ║
         ║  🖧  server-3                      ║
         ╚═══════════════════════════════════╝
```

---

## Installation et démarrage

```bash
da up ssh-lab --build       # premier démarrage
da up ssh-lab               # redémarrage rapide
da restart ssh-lab          # après modification de cluster.conf
da restart ssh-lab --build  # après modification d'un Dockerfile
da down ssh-lab
```

### Activer l'autocomplétion côté hôte (une seule fois)

```bash
echo 'source ~/docker-apps/ssh-lab/completions.bash' >> ~/.bashrc
source ~/docker-apps/ssh-lab/completions.bash
```

---

## `cluster-exec.sh` — Broadcast via docker exec depuis l'hôte

**Syntaxe : `./cluster-exec.sh <groupe|nœud> <commande>`**

```bash
./cluster-exec.sh all      "hostname && uptime"
./cluster-exec.sh servers  "apk add --no-cache curl && curl -s ifconfig.me"
./cluster-exec.sh clients  "ls /root/.ssh/"
./cluster-exec.sh gateways "ss -tlnp | grep :22"
./cluster-exec.sh master   "lab-exec servers 'hostname'"
./cluster-exec.sh server-2 "df -h /"
./cluster-exec.sh client-1 "ssh -J root@gateway-1 root@server-3 hostname"
```

Avec complétion :
```
$ ./cluster-exec.sh <TAB>
all  master  clients  gateways  servers  client-1  client-2  gateway-1  server-1  server-2  server-3
```

---

## `upload.sh` — Upload de fichiers depuis l'hôte

**Syntaxe : `./upload.sh <groupe> <fichier>`**

```bash
./upload.sh all     deploy.tar.gz
./upload.sh master  admin-tool.sh
./upload.sh servers app-bundle.tar.gz
./upload.sh clients client-config.sh
./upload.sh gateways gw-rules.sh
```

Avec complétion :
```
$ ./upload.sh <TAB>
all  master  clients  gateways  servers

$ ./upload.sh servers <TAB>
app.tar.gz   config.sh   deploy/   ...    ← complétion de fichiers locaux
```

Dans le conteneur :
```bash
docker exec ssh-server-1 tar xzf /uploads/role/app-bundle.tar.gz -C /root/
```

---

## `lab-exec` — Broadcast SSH depuis le master

**Syntaxe : `lab-exec <groupe|nœud> <commande>`**

```bash
docker exec -it ssh-master bash

# Autocomplétion active dès l'ouverture du shell :
lab-exec <TAB>
# → all  clients  gateways  servers  client-1  client-2  gateway-1  server-1  ...

lab-exec all      "hostname"
lab-exec servers  "apk add --no-cache htop"
lab-exec server-2 "cat /etc/resolv.conf"
lab-exec gateways "ss -tlnp"
```

---

## Connexions SSH manuelles

```bash
# Hôte → GATEWAY
ssh root@localhost -p 2221

# Master → tout nœud (clé admin, sans mot de passe)
docker exec -it ssh-master bash
ssh server-1 ; ssh client-2 ; ssh gateway-1

# CLIENT → SERVER via jump host
docker exec -it ssh-client-1 bash
ssh -J root@gateway-1 root@server-2

# Hôte → SERVER via double saut
ssh -J root@localhost:2221 root@server-3

# Vérifier l'accès Internet sur les SERVERs
./cluster-exec.sh servers "apk update && echo OK"
```

---

## Persistence

| Volume nommé | Chemin | Contenu |
|---|---|---|
| `sshlab_master_home` | `/root` | Clés, scripts |
| `sshlab_master_etcssh` | `/etc/ssh` | Clés hôtes sshd |
| `sshlab_client_N_home` | `/root` | Clés, scripts |
| `sshlab_gateway_N_{home,etcssh}` | `/root`, `/etc/ssh` | Clés, sshd |
| `sshlab_server_N_{home,etcssh}` | `/root`, `/etc/ssh` | Clés, sshd |

```bash
docker volume ls -f name=sshlab_
docker volume rm $(docker volume ls -q -f name=sshlab_)
```

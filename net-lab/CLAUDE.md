# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`net-lab` is one cluster of the Docker Apps Manager monorepo. The repo-level
`../CLAUDE.md` documents the generic `da` workflow shared by all clusters; this
file covers what is specific to `net-lab`.

## What this cluster is

A simulated home network: a **box/router** container doing real NAT, plus Linux
nodes in four roles (box / gateway / server / nas / client) across three Docker
networks (WAN / LAN / DMZ). Used to practice port-forwarding, jump hosts and DMZ
isolation. All non-box nodes share **one common image** (`config/node/`); the box
has its own (`config/box/`).

## Commands

```bash
da up net-lab --build       # first start
da restart net-lab          # after editing topology.conf or box.conf [STRUCTUREL] fields
da restart net-lab --build  # after editing a Dockerfile / entrypoint
da down net-lab

# Box "IHM" (the ONLY way to touch the router)
./box-apply.sh              # validate box.conf, push it, hot-reload DMZ + port-forwards
./box-status.sh             # show applied config + live iptables

# Nodes (never the box)
./cluster-exec.sh <group|node> "<cmd>"   # parallel docker exec; groups: all|gateway|servers|clients|nas
./upload.sh <group> <file>               # drop file into /uploads (ro)
./volumes-rm.sh                          # wipe netlab_ volumes
```

Auth on every node: `root` / `ROOT_PASSWORD` (password auth, no keys
pre-distributed). Default test path is **from a `client` container** (on macOS the
host can't route to Docker networks, so clients are the "external Internet" actors).

## Architecture

### Two configs → generated compose

`config/docker-compose.yaml` is **auto-generated** by `config/pre-up.sh` from two
hand-edited files — never edit the compose by hand:

- **`config/topology.conf`** — "the hardware": `N_SERVERS`, `N_CLIENTS`,
  `ROOT_PASSWORD`, `LOG_LEVEL`. (nas=1, gateway=1 are fixed.)
- **`config/box.conf`** — "the router IHM": `PUBLIC_IP`, the WAN/LAN/DMZ subnets,
  static `LEASES` (`"name:ip"`, else auto-assigned), `DMZ_HOST`, and `FORWARDS`
  (`"proto:public_port:target:target_port"`).

`pre-up.sh` resolves every node's IP (lease or auto), builds a `HOSTMAP`
(`name=ip;…`) passed to the box as env, copies `box.conf` → `shared/box/box.conf`
(the applied copy the box reads), and emits networks (static ipam) + services.

### The box is special — touched ONLY via its IHM

The box must never be reached by `docker exec` / `cluster-exec.sh` (those tools
reject it). Its lifecycle:

- It bind-mounts `shared/box/box.conf` (ro) and runs `box apply` on start.
- The in-container `box` CLI (`config/box/box`) has `apply` (flush + rebuild
  iptables from box.conf + `$HOSTMAP`) and `status`.
- Host `box-apply.sh` copies `config/box.conf` → `shared/box/box.conf` then
  `docker exec net-lab-box box apply` → **hot reload**. It warns on `[STRUCTUREL]`
  drift (PUBLIC_IP / subnets / LEASES) since those need `da restart` (ipam is fixed
  at container create). So `config/box.conf` is the editable source; the box reads
  the pushed copy — like changing a field in an IHM vs clicking Apply.

### Routing / firewall model (the delicate part)

- Box has static IPs on all three nets: `PUBLIC_IP` on WAN, **`.1`** on LAN and DMZ
  (so the Docker bridge gateway is forced to `.254` for LAN/DMZ in the generated
  ipam — a container can't take the bridge's gateway IP).
- Box: `ip_forward=1`, `NET_ADMIN`. iptables = DNAT per FORWARD rule (matched on
  `-d $PUBLIC_IP --dport`), MASQUERADE toward LAN/DMZ (clean return path), and a
  FORWARD chain implementing the DMZ matrix (`DMZ→LAN` DROP, `LAN→DMZ` ACCEPT,
  DNAT'd inbound ACCEPT, established ACCEPT).
- **Egress is Docker's**, not the box: nodes keep Docker's default route for
  Internet. Therefore LAN nodes (gateway, servers) get **`cap_add: NET_ADMIN`** and
  their entrypoint adds a static route `DMZ_SUBNET via box` so `LAN→DMZ` works.
  NAS/clients need no route changes (NAS has no LAN route → `DMZ→LAN` is also
  blocked by routing, belt-and-suspenders).
- Consequence: forwarded/inter-segment traffic is MASQUERADEd, so targets see the
  box IP as source. DNS resolves per-network (same segment by name, cross-segment
  by IP).

### Node image (one image, role via env)

`config/node/entrypoint.sh` keys off `NODE_ROLE`: sets root password + sshd
(LogLevel from `LOG_LEVEL`), runs `sshd -D` on all roles; LAN roles add the DMZ
route (needs `DMZ_SUBNET` + `BOX_LAN_IP` env); `nas` also starts a demo
`python3 -m http.server 8080`. Editing an entrypoint requires `--build`.

### Persistence

Named volumes `netlab_<node>_{home,etcssh}` (explicit `name:` to avoid Compose's
project prefix) survive `da down`. The box is stateless (rebuilds rules from
config each start).

## Gotchas

- A manually-started instance (`docker compose up` from `config/`) uses project
  name `config`; its WAN/LAN/DMZ networks will **collide on subnets** with a later
  `da up net-lab`. Always `docker compose -f config/docker-compose.yaml down -v`
  after manual testing.
- `box apply` does `iptables -t nat -F` inside the box namespace, which also clears
  Docker's embedded-DNS nat rules there — harmless, the box resolves nothing by name.
- Anonymity: keep this lab generic. Use RFC5737 (`203.0.113.0/24`) for "public"
  IPs; no real hostnames/IPs, no personal references in docs or comments.

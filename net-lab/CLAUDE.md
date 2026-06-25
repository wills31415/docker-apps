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
da up net-lab --build       # first start (or fresh install after ./reset-like flow)
da restart net-lab          # down + up = HARD cycle = wipes node state ⚠ (see Gotchas)
da down net-lab

# Soft cycle (= true reboot, ALL node state preserved — see Persistence)
./reboot.sh                 # stop + start (writable layer of each container survives)
./stop.sh                   # docker compose stop  (containers paused, kept)
./start.sh                  # docker compose start (resume kept containers)
# ⚠ ./{stop,start,reboot}.sh are TEMPORARY pending `da start/stop` subcommands.

# Push hot-tunable topology.conf changes (LOG_LEVEL, ROOT_PASSWORD) onto live
# nodes WITHOUT recreate (writable layer preserved): regenerates the bind-
# mounted runtime.conf, then rms the marker + docker restart on each target.
./reprovision.sh <group|node>

# Box "IHM" (the ONLY way to touch the router)
./box-apply.sh              # validate box.conf, push it, hot-reload DMZ + port-forwards
./box-status.sh             # show applied config + live iptables + packet counters
./box-status.sh conntrack   # live NAT translations (DNAT / MASQUERADE)
./box-status.sh --watch     # refresh status (or conntrack) every 2s

# Nodes (never the box)
./cluster-exec.sh <group|node> "<cmd>"   # parallel docker exec; groups: all|gateway|servers|clients|nas
./upload.sh <group> <file>               # drop file into /uploads (ro)
./volumes-rm.sh                          # legacy: wipe any leftover netlab_ volumes (nodes no longer have named volumes)
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
- **`config/box.conf`** — "the router IHM": `PUBLIC_IP`, `EGRESS_VIA_BOX` (0/1
  egress toggle), the WAN/LAN/DMZ subnets, static `LEASES` (`"name:ip"`, else
  auto-assigned), `DMZ_HOST` (real "DMZ host": catch-all DNAT for inbound ports
  not explicitly forwarded), and `FORWARDS` (`"proto:public_port:target:target_port"`).

`pre-up.sh` resolves every node's IP (lease or auto), builds a `HOSTMAP`
(`name=ip;…`) passed to the box as env, copies `box.conf` → `shared/box/box.conf`
(the applied copy the box reads), and emits networks (static ipam) + services.

### The box is special — touched ONLY via its IHM

The box must never be reached by `docker exec` / `cluster-exec.sh` (those tools
reject it). Its lifecycle:

- It bind-mounts `shared/box/box.conf` (ro) and runs `box apply` on start.
- The in-container `box` CLI (`config/box/box`) has `apply` (flush + rebuild
  iptables from box.conf + `$HOSTMAP`), `status` (now also shows the egress mode
  + FORWARD packet counters), and `conntrack` (live NAT table).
- Host `box-apply.sh` copies `config/box.conf` → `shared/box/box.conf` then
  `docker exec net-lab-box box apply` → **hot reload**. It warns on `[STRUCTUREL]`
  drift (PUBLIC_IP / subnets / LEASES / EGRESS_VIA_BOX) since those need `da restart`
  (ipam + each node's default route are fixed at container create). So
  `config/box.conf` is the editable source; the box reads the pushed copy — like
  changing a field in an IHM vs clicking Apply.

### Routing / firewall model (the delicate part)

- Box has static IPs on all three nets: `PUBLIC_IP` on WAN, **`.1`** on LAN and DMZ
  (so the Docker bridge gateway is forced to `.254` for LAN/DMZ in the generated
  ipam — a container can't take the bridge's gateway IP).
- Box: `ip_forward=1`, `NET_ADMIN`. iptables = DNAT per FORWARD rule (matched on
  `-d $PUBLIC_IP --dport`), an optional `DMZ_HOST` catch-all DNAT (all remaining
  inbound tcp/udp → that host, added AFTER explicit forwards so they win), a
  FORWARD chain implementing the DMZ matrix (`DMZ→LAN` DROP, `LAN→DMZ` ACCEPT,
  DNAT'd inbound ACCEPT, established ACCEPT), plus mode-dependent SNAT (below).
- **Egress mode is a toggle (`EGRESS_VIA_BOX`)**:
  - `0` (default): egress is **Docker's**, not the box — nodes keep Docker's
    default route for Internet. The box MASQUERADEs traffic it pushes toward
    LAN/DMZ (`POSTROUTING -d LAN/DMZ`) so the return path is clean even though
    nodes don't route back through it. Consequence: forwarded/inter-segment
    traffic is SNATed → targets see the **box IP** as source.
  - `1`: the box is the **default gateway** of LAN/DMZ nodes (entrypoint does
    `ip route replace default via $BOX_GW_IP`). SNAT happens only toward the
    outside (`POSTROUTING -s LAN/DMZ ! -d LAN ! -d DMZ`), so internal traffic
    (LAN↔DMZ, inbound DNAT) keeps the **real source IP** and everything funnels
    through the box (single observation point). Toggling is `[STRUCTUREL]`
    (node routes are set at start) → `da restart`.
- LAN nodes (gateway, servers) get `cap_add: NET_ADMIN` + a static route
  `DMZ_SUBNET via box` (both modes, so `LAN→DMZ` works). NAS now also gets
  `NET_ADMIN` + `BOX_GW_IP` (used only when `EGRESS_VIA_BOX=1`); in mode 0 it has
  no LAN route → `DMZ→LAN` is also blocked by routing (belt-and-suspenders), in
  mode 1 it default-routes via the box → `DMZ→LAN` is blocked by the FORWARD DROP.
  Clients (WAN) are never rerouted — they are the external Internet.
- DNS resolves per-network (same segment by name, cross-segment by IP), both modes.

### Node image (one image, role via env)

`config/node/entrypoint.sh` is **monolithic with a first-boot guard** — it runs
on every container start but its **phase 1** (provisioning: write
`/etc/ssh/sshd_config` with `Include /etc/ssh/sshd_config.d/*.conf` at TOP
per Debian convention, `chpasswd` root, `ssh-keygen -A`, write NAS demo HTML)
runs only when the marker `/var/lib/net-lab/.provisioned` is absent — i.e.
only on a freshly-created container OR after `./reprovision.sh` (which rms
the marker). Its **phase 2** (every boot, idempotent) keys off `NODE_ROLE`:
LAN roles add the DMZ route (needs `DMZ_SUBNET` + `BOX_LAN_IP`), LAN+DMZ
roles switch default route to the box when `EGRESS_VIA_BOX=1` (needs
`BOX_GW_IP`), `nas` starts a demo `python3 -m http.server 8080`, then
`exec sshd -D`.

**Hot-tunable vs structural config** :
- **Structural** (env vars, set at container create, require recreate
  to change): `NODE_ROLE`, `NODE_NAME`, `BOX_GW_IP`, `EGRESS_VIA_BOX`,
  `DMZ_SUBNET`, `BOX_LAN_IP`. Changing these in `box.conf`/`topology.conf`
  ⇒ `da restart` (wipes state, fresh provision).
- **Hot-tunable** (`shared/node/runtime.conf`, bind-mounted ro at
  `/net-lab/runtime.conf`, regenerated by `pre-up.sh` or `reprovision.sh`):
  `ROOT_PASSWORD`, `LOG_LEVEL`. Changing these in `topology.conf` +
  `./reprovision.sh <target>` ⇒ runtime.conf rewritten, marker rm'd,
  container restarted, phase 1 re-sources the file ⇒ **propagation
  without recreate, writable layer preserved**.

The entrypoint is **bind-mounted from the host** at `/net-lab/entrypoint.sh`
(Dockerfile creates the mountpoint) — same pattern as `box.conf` and
`runtime.conf` — so editing it = `./reboot.sh`, **never `--build` needed
for the entrypoint**. The node image ships a network toolbox
(ping/traceroute/mtr/dig/tcpdump/nc/iperf3/nmap); the box image adds
tcpdump + conntrack. Editing the Dockerfile (e.g. adding a package) still
needs a fresh install: `da down && da up --build`.

### Persistence — VM semantics via stop/start

**Nodes have no named volumes.** Their persistence comes from the container's
writable layer, which **Docker preserves across `docker compose stop`/`start`**
but **destroys on `docker compose down`/`up` (= containers recreated)**.

- **Soft cycle** (`./reboot.sh` = stop + start): **everything** in the node's
  filesystem survives — config in `/etc`, users, `/home`, logs in `/var/log`,
  packages installed via `apt install`, top-level dir restructurations
  (`rm /home && ln -s /users /home` survives a reboot), the first-boot marker.
  This is the **true reboot** semantic, fidèle to a real machine.
- **Hard cycle** (`da restart` = down + up, or `da up --build`):
  containers are recreated from the image → writable layer destroyed → marker
  gone → phase 1 of entrypoint runs again. This is the **fresh install**
  semantic. Use only when you've changed `topology.conf`/`box.conf` structural
  fields (env vars, IPAM) or the image (Dockerfile).
- To propagate a `topology.conf` change to an *already installed* node without
  wiping everything else, use `./reprovision.sh <node>` — it just rms the
  marker and restarts the container.

The box stays stateless (rebuilds rules from config each start) and is unaffected
by this model: it has no writable layer worth persisting.

## Gotchas

- **`da restart net-lab` wipes node filesystem state.** It does `compose down`
  + `up` ⇒ containers recreated ⇒ writable layer destroyed ⇒ users, installed
  packages, tweaks to `/etc`, everything an external tool wrote — all gone.
  For a true reboot that preserves state, use `./reboot.sh` (or `da start/stop`
  when those land). Reserve `da restart` for actual fresh installs.
- **Hot-tunable `topology.conf` values (`LOG_LEVEL`, `ROOT_PASSWORD`) need
  `./reprovision.sh <target>` to propagate to running nodes** — a plain
  `./reboot.sh` won't update `/etc/ssh/sshd_config` or the root password
  (phase 1 has already run, marker present, file unchanged). `reprovision.sh`
  regenerates `shared/node/runtime.conf` from `topology.conf`, rms the
  marker on each target, restarts the container ⇒ phase 1 re-sources the
  new file. Other admin state on those nodes is preserved.
- A manually-started instance (`docker compose up` from `config/`) uses project
  name `config`; its WAN/LAN/DMZ networks will **collide on subnets** with a later
  `da up net-lab`. Always `docker compose -f config/docker-compose.yaml down -v`
  after manual testing.
- `box apply` does `iptables -t nat -F` inside the box namespace, which also clears
  Docker's embedded-DNS nat rules there — harmless, the box resolves nothing by name.
- Anonymity: keep this lab generic. Use RFC5737 (`203.0.113.0/24`) for "public"
  IPs; no real hostnames/IPs, no personal references in docs or comments.

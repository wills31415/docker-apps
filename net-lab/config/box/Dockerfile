# ============================================================
#  net-lab — BOX (routeur / "box internet")
#  Rôle : NAT + DNAT (redirections) + pare-feu DMZ entre WAN/LAN/DMZ
#  Réseaux : wan + lan + dmz   |   cap : NET_ADMIN
#  NE PAS administrer via docker exec : uniquement via box-apply.sh
# ============================================================
FROM debian:12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tini \
        iptables \
        iproute2 \
        procps \
 && rm -rf /var/lib/apt/lists/*

COPY box /usr/local/bin/box
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/box /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

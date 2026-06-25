# ============================================================
#  net-lab — NODE (image commune : nas / gateway / server / client)
#  Le rôle est choisi à l'exécution via la variable NODE_ROLE.
#  Petit Linux + boîte à outils réseau : ssh, curl, python3, et de
#  quoi diagnostiquer (ping, traceroute, mtr, dig, tcpdump, nc,
#  iperf3, nmap). ICMP/raw-socket OK : Docker garde la cap NET_RAW.
# ============================================================
FROM debian:12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tini \
        openssh-server \
        openssh-client \
        iproute2 \
        sudo \
        curl \
        ca-certificates \
        python3 \
        nano \
        iputils-ping \
        traceroute \
        mtr-tiny \
        dnsutils \
        tcpdump \
        netcat-openbsd \
        iperf3 \
        nmap \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd /root/.ssh /net-lab \
 && chmod 700 /root/.ssh

EXPOSE 22

# entrypoint.sh est bind-monté depuis l'hôte vers /net-lab/ par le compose
# (pattern identique à box.conf). Itérer dessus = `./reboot.sh`, jamais
# `--build`. /net-lab/ existe juste comme point de montage.
ENTRYPOINT ["/usr/bin/tini", "--", "/net-lab/entrypoint.sh"]

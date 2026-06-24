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
 && mkdir -p /run/sshd /root/.ssh \
 && chmod 700 /root/.ssh

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

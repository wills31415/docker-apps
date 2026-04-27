# ============================================================
#  MASTER — ssh-lab v6
#  Rôle   : Nœud d'administration SSH du cluster
#  Réseau : client-net ET server-net
#  OS     : Debian 12 (bookworm)
#  sshd   : OUI
# ============================================================
FROM debian:12

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tini \
        openssh-server \
        openssh-client \
        sudo \
        nano \
        make \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash admin \
 && echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin \
 && chmod 440 /etc/sudoers.d/admin \
 && mkdir -p /root/.ssh /home/admin/.ssh /run/sshd \
 && chmod 700 /root/.ssh /home/admin/.ssh

COPY lab-exec /usr/local/bin/lab-exec
RUN chmod +x /usr/local/bin/lab-exec

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

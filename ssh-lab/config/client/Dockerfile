# ============================================================
#  CLIENT — ssh-lab v6
#  Rôle   : Initiateur de connexions SSH
#  Réseau : client-net uniquement
#  OS     : Debian 12 (bookworm)
#  sshd   : NON
# ============================================================
FROM debian:12

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tini \
        openssh-client \
        sudo \
        nano \
        make \
 && rm -rf /var/lib/apt/lists/* \
 # Utilisateur admin avec sudo sans mot de passe
 && useradd -m -s /bin/bash admin \
 && echo "admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/admin \
 && chmod 440 /etc/sudoers.d/admin \
 # Répertoires SSH
 && mkdir -p /root/.ssh /home/admin/.ssh \
 && chmod 700 /root/.ssh /home/admin/.ssh \
 && chown admin:admin /home/admin/.ssh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

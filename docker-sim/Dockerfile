# syntax=docker/dockerfile:1.6

ARG AMI_VARIANT=base
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    git-lfs \
    awscli \
    build-essential \
    python3-venv \
    python3-pip \
    sudo \
    ufw \
    auditd \
    fail2ban \
    unattended-upgrades \
    logrotate \
    chrony \
    xz-utils \
    openssh-server \
    locales \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash ubuntu \
  && mkdir -p /opt/venvs /usr/share/examples/spark /opt/nix/flake /opt/nix/envs /opt/nix/langs \
  && chown -R ubuntu:ubuntu /opt/venvs \
  && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN printf '#!/bin/sh\necho "[systemctl stub] $@" >&2\nexit 0\n' > /usr/local/bin/systemctl \
  && chmod +x /usr/local/bin/systemctl

RUN curl -fsSL -o /tmp/install-nix.sh https://nixos.org/nix/install \
  && yes | sh /tmp/install-nix.sh --no-daemon \
  && rm -f /tmp/install-nix.sh

ENV PATH=/root/.nix-profile/bin:/root/.nix-profile/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

COPY harden.sh /tmp/harden.sh
COPY scripts/spark-java.sh /tmp/spark-java.sh
COPY examples/pyspark_basic.py /tmp/pyspark_basic.py
COPY examples/pyspark_pi.py /tmp/pyspark_pi.py
COPY nix/flake.nix /tmp/flake.nix
COPY docker-sim/run-provision.sh /usr/local/bin/run-provision.sh

RUN chmod +x /usr/local/bin/run-provision.sh \
  && /usr/local/bin/run-provision.sh common

RUN /usr/local/bin/run-provision.sh ${AMI_VARIANT}

# Match EC2 runtime: ubuntu user with passwordless sudo (root used only for build steps above)
USER ubuntu
WORKDIR /home/ubuntu

CMD ["/bin/bash"]

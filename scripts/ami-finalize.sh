#!/usr/bin/env bash
# ami-finalize.sh — MUST be the last Packer provisioner step.
# Generates the package manifest, installs legal notices, and scrubs build
# artefacts so each customer instance starts from a clean, anonymous state.
#
# Usage: sudo /tmp/ami-finalize.sh <base|pro>
set -euo pipefail

VARIANT="${1:-base}"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ==============================
# Package Manifest
# ==============================
sudo mkdir -p /usr/share/BUILD_INFO

{
  cat <<EOF
CPU DS/ML AMI (${VARIANT}) — Package Manifest
Built:          ${BUILT_AT}
Nixpkgs channel: nixos-25.05

EOF
  echo "--- Python 3.11 (${VARIANT} env) ---"
  /opt/nix/envs/${VARIANT}/bin/python -m pip list --format=columns 2>/dev/null \
    || echo "(env not found)"

  echo ""
  echo "--- Python 3.12 (${VARIANT}-py312 env) ---"
  /opt/nix/envs/${VARIANT}-py312/bin/python -m pip list --format=columns 2>/dev/null \
    || echo "(env not found)"

  echo ""
  echo "--- Python 3.13 (${VARIANT}-py313 env) ---"
  /opt/nix/envs/${VARIANT}-py313/bin/python -m pip list --format=columns 2>/dev/null \
    || echo "(env not found)"

  echo ""
  echo "--- System packages (dpkg) ---"
  dpkg-query -W -f='${binary:Package} ${Version}\n' 2>/dev/null | sort \
    || echo "(dpkg-query failed)"
} | sudo tee /usr/share/BUILD_INFO/packages.txt >/dev/null

sudo chmod 644 /usr/share/BUILD_INFO/packages.txt

# ==============================
# EULA / Subscriber License
# ==============================
sudo tee /usr/share/BUILD_INFO/EULA.txt >/dev/null <<'EOF'
CPU DS/ML AMI — Subscriber License Agreement
=============================================
Copyright (c) 2025. All rights reserved.

AUTHORIZED USE ONLY
This Amazon Machine Image (AMI) is licensed, not sold, to authorized
subscribers through AWS Marketplace. Your subscription grants a
non-exclusive, non-transferable right to launch instances of this AMI
within your own AWS account solely for your internal business purposes.

PROHIBITED ACTIONS
The following are strictly prohibited without prior written consent:
  - Copying, modifying, or redistributing this AMI or derived images
  - Reverse engineering, decompiling, or disassembling AMI contents
  - Reselling, sublicensing, or making this AMI available to third parties
  - Removing or altering copyright notices, license terms, or attributions
  - Launching instances of this AMI outside of an active Marketplace
    subscription

OPEN-SOURCE COMPONENTS
This AMI bundles open-source software under their respective upstream
licenses (Apache 2.0, MIT, BSD, PSF, etc.). Those licenses are not
affected by this agreement. See:
  /usr/share/BUILD_INFO/packages.txt  — full package list
  /usr/share/OSS_NOTICES.md          — open-source attributions

DISCLAIMER
THIS AMI IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES,
OR OTHER LIABILITY ARISING FROM USE OF THIS AMI.

By launching instances of this AMI you agree to these terms.
EOF
sudo chmod 644 /usr/share/BUILD_INFO/EULA.txt

# ==============================
# MOTD — displayed at every SSH login
# ==============================
sudo tee /etc/update-motd.d/99-ami-notice >/dev/null <<'EOF'
#!/bin/sh
cat <<'NOTICE'

 +------------------------------------------------------------+
 |          CPU DS/ML AMI  --  Authorized Use Only           |
 |   Copyright (c) 2025. Licensed via AWS Marketplace.       |
 |   Reverse engineering or redistribution is prohibited.    |
 |   Full terms: /usr/share/BUILD_INFO/EULA.txt              |
 +------------------------------------------------------------+

NOTICE
EOF
sudo chmod 755 /etc/update-motd.d/99-ami-notice

# Disable the default Ubuntu "welcome" noise to keep MOTD clean
sudo chmod -x /etc/update-motd.d/10-help-text 2>/dev/null || true
sudo chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true

# ==============================
# AMI Scrub  (MUST STAY LAST)
# ==============================

# Remove SSH host keys — new keys are generated on each customer's first boot
sudo rm -f /etc/ssh/ssh_host_*

# Reset cloud-init so it runs fresh on each new instance (re-injects keypairs, etc.)
sudo cloud-init clean --logs 2>/dev/null || true
sudo rm -rf /var/lib/cloud/instances/* 2>/dev/null || true

# Clear shell history for all users
sudo truncate -s 0 /root/.bash_history 2>/dev/null || true
sudo truncate -s 0 /home/ubuntu/.bash_history 2>/dev/null || true
history -c 2>/dev/null || true

# Remove build temp files
sudo rm -f /tmp/harden.sh /tmp/ami-finalize.sh /tmp/install-nix.sh 2>/dev/null || true
sudo rm -rf /tmp/awscliv2* /tmp/aws 2>/dev/null || true

# Truncate (not delete) log files — preserves logrotate config compatibility
for log in \
  /var/log/syslog \
  /var/log/auth.log \
  /var/log/kern.log \
  /var/log/cloud-init.log \
  /var/log/cloud-init-output.log \
  /var/log/dpkg.log \
  /var/log/apt/history.log \
  /var/log/apt/term.log; do
  sudo truncate -s 0 "$log" 2>/dev/null || true
done

# Reset machine-id — a new unique ID is generated on each fresh instance boot
sudo truncate -s 0 /etc/machine-id 2>/dev/null || true
[ -f /var/lib/dbus/machine-id ] && sudo truncate -s 0 /var/lib/dbus/machine-id 2>/dev/null || true

echo "AMI finalization complete: ${VARIANT} / ${BUILT_AT}"

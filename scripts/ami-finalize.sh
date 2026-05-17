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
# SBOM (CycloneDX JSON)
# ==============================
# Generates a minimal CycloneDX 1.4 SBOM listing all pip-installed packages.
# Enterprise and government buyers increasingly require an SBOM for procurement.
{
  cat <<HEADER
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "timestamp": "${BUILT_AT}",
    "component": { "type": "container", "name": "cpu-ds-ml-ami-${VARIANT}" }
  },
  "components": [
HEADER
  # Emit one JSON object per pip package (primary env)
  /opt/nix/envs/${VARIANT}/bin/python -m pip list --format=json 2>/dev/null | \
    python3 -c "
import json, sys
pkgs = json.load(sys.stdin)
lines = []
for p in pkgs:
    lines.append('    {\"type\":\"library\",\"name\":\"' + p['name'] + '\",\"version\":\"' + p['version'] + '\"}')
print(',\n'.join(lines))
" || true
  echo "  ]"
  echo "}"
} | sudo tee /usr/share/BUILD_INFO/sbom.cyclonedx.json >/dev/null
sudo chmod 644 /usr/share/BUILD_INFO/sbom.cyclonedx.json

# ==============================
# EULA / Subscriber License
# ==============================
sudo tee /usr/share/BUILD_INFO/EULA.txt >/dev/null <<'EOF'
CPU DS/ML AMI — License Notice
===============================
Copyright (c) 2025. All rights reserved.

GOVERNING AGREEMENT
This AMI is licensed under the AWS Standard Contract for AWS Marketplace
(Standard Contract). By subscribing and launching instances of this AMI
you agree to the Standard Contract terms.

Full terms:
  https://aws.amazon.com/marketplace/pp/prodview-standard-contract

QUICK REFERENCE — KEY RESTRICTIONS
  - Authorized use only: launch within your own AWS account under an
    active Marketplace subscription
  - No copying, redistribution, or resale of this AMI or derived images
  - No reverse engineering or removal of copyright notices
  - No sublicensing or making this AMI available to third parties outside
    your AWS account

OPEN-SOURCE COMPONENTS
This AMI bundles open-source software (PyTorch, TensorFlow, Spark,
Ubuntu packages, Nix derivations, etc.) under their respective upstream
licenses (Apache 2.0, MIT, BSD, PSF, GPL, etc.). Those licenses are not
affected by the Standard Contract. See:
  /usr/share/BUILD_INFO/packages.txt       — full package list
  /usr/share/BUILD_INFO/sbom.cyclonedx.json — CycloneDX SBOM
  /usr/share/OSS_NOTICES.md               — open-source attributions

EXPORT CONTROL
This software contains encryption components classified under ECCN
5D002.c.1 and is distributed under License Exception ENC (mass-market
encryption). See /usr/share/BUILD_INFO/EAR-classification.txt for
details.
EOF
sudo chmod 644 /usr/share/BUILD_INFO/EULA.txt

# ==============================
# EAR Export Classification Notice (baked in for compliance records)
# ==============================
sudo tee /usr/share/BUILD_INFO/EAR-classification.txt >/dev/null <<'EOF'
CPU DS/ML AMI — U.S. Export Administration Regulations (EAR) Classification
=============================================================================

ECCN:             5D002.c.1
                  (Software for encryption / cryptanalysis)

License Exception: ENC — Mass-market encryption
                  (15 CFR Part 740, Supplement 1 to Part 742)

Basis: This AMI bundles publicly available, mass-market cryptographic
software (OpenSSL, OpenSSH, Python cryptography, AWS CLI TLS). These
components:
  - Are widely available from public sources (Ubuntu, PyPI, GitHub)
  - Do not provide custom cryptographic implementations
  - Are not designed for military or intelligence use
  - Meet the ENC exception criteria at 15 CFR 740.17(b)(1)

Encrypted components included:
  - OpenSSL (Ubuntu libssl3, libssl-dev)     — TLS/SSL
  - OpenSSH (Ubuntu openssh-server/client)   — SSH transport
  - Python cryptography package (PyPI)       — TLS, x509, symmetric
  - AWS CLI v2                               — HTTPS/TLS to AWS APIs
  - Nix daemon                               — TLS to cache.nixos.org
  - curl / wget / ca-certificates           — HTTPS transport

Annual self-classification report: U.S. exporters distributing ENC
mass-market items must submit an annual report to BIS via SNAP-R
(https://snapr.bis.doc.gov) by February 1 each year for items sold
in the prior calendar year. Report type: ANNUAL SELF-CLASSIFICATION
REPORT FOR ENCRYPTION ITEMS.

Restricted destinations: This software may not be exported to countries
subject to U.S. embargo or comprehensive sanctions (Cuba, Iran, North
Korea, Russia, Syria, Crimea). See current OFAC list:
  https://www.treasury.gov/ofac/downloads/sdnlist.txt

AWS Marketplace automatically blocks purchases from restricted regions.

Last reviewed: 2026-05-17
EOF
sudo chmod 644 /usr/share/BUILD_INFO/EAR-classification.txt

# ==============================
# MOTD — displayed at every SSH login
# ==============================
sudo tee /etc/update-motd.d/99-ami-notice >/dev/null <<'EOF'
#!/bin/sh
cat <<'NOTICE'

 +------------------------------------------------------------+
 |          CPU DS/ML AMI  --  Authorized Use Only           |
 |   Copyright (c) 2025. Licensed via AWS Standard Contract. |
 |   Reverse engineering or redistribution is prohibited.    |
 |   Full terms: /usr/share/BUILD_INFO/EULA.txt              |
 +------------------------------------------------------------+
 |  Build: $(cat /usr/share/BUILD_INFO 2>/dev/null || echo unknown)
 |  Security advisories: /usr/share/BUILD_INFO/SECURITY.md   |
 +------------------------------------------------------------+

NOTICE
EOF
sudo chmod 755 /etc/update-motd.d/99-ami-notice

# Disable the default Ubuntu "welcome" noise to keep MOTD clean
sudo chmod -x /etc/update-motd.d/10-help-text 2>/dev/null || true
sudo chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true

# ==============================
# Security Advisory (baked in — MOTD points here)
# ==============================
# Copy the repo SECURITY.md into the AMI so customers can read advisories
# and remediation steps without needing internet access.
if [ -f /tmp/SECURITY.md ]; then
  sudo cp /tmp/SECURITY.md /usr/share/BUILD_INFO/SECURITY.md
  sudo chmod 644 /usr/share/BUILD_INFO/SECURITY.md
fi

# ==============================
# Disk Space Cleanup
# ==============================

# Nix garbage collection: removes build-time-only derivations that are no longer
# reachable from any GC root. Frees 1-3 GB of store paths from intermediate
# build steps that have no value in the final AMI.
echo "Running nix garbage collection..."
sudo bash -lc 'source /etc/profile.d/nix.sh && nix-collect-garbage -d' 2>/dev/null || true
# nix store optimise intentionally omitted: hard-linking identical store paths
# saves ~10-15% space but takes 5-15 min on a full ML store. The GC above
# already removes 1-3 GB of build-time-only derivations — that is the
# higher-value operation. Running optimise would noticeably extend build time.

# Pip wheel cache: pip caches downloaded wheels under /root/.cache/pip and
# /home/ubuntu/.cache/pip. After build these serve no purpose — on the running
# AMI pip will re-download when needed. Purging saves 500 MB - 4 GB (pro build).
sudo rm -rf /root/.cache/pip 2>/dev/null || true
sudo rm -rf /home/ubuntu/.cache/pip 2>/dev/null || true

# APT cache: packages downloaded during apt-get install steps
sudo apt-get clean 2>/dev/null || true
sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || true

# Trivy vuln DB: downloaded on first ami-scan run, not needed at build time
sudo rm -rf /root/.cache/trivy 2>/dev/null || true

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

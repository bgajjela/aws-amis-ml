# CPU DS/ML AMI (Ubuntu 22.04) — Hardened + Nix Managed

This repository builds a hardened Ubuntu 22.04 AMI for data science and ML workloads on CPU, with fully reproducible language/runtime environments managed by Nix.

## Highlights
- Nix-managed envs under `/opt/nix` with symlinks in `/usr/local/bin`:
  - Python: 3.11, 3.12, 3.13 (base and pro envs)
  - Java 17 (OpenJDK), Apache Spark (spark-submit, pyspark)
  - Julia, R, Go
- Security hardening (CIS-aligned Level 2):
  - SSH hardened (no passwords/root), strong crypto, legal banners
  - UFW default deny inbound with rate-limited SSH
  - sysctl kernel/network hardening, tmpfs for /tmp and /var/tmp, hardened /dev/shm
  - AppArmor enforcing, auditd immutable rules, AIDE initialized
  - logrotate compression, journald persistent+compressed with size caps
  - Elevated ulimits (login shells + systemd defaults)
- Minimal PySpark examples in `/usr/share/examples/spark`

## Build Architecture

```
                   C P U  ·  D S / M L  ·  A M I   B u i l d   P i p e l i n e
  ═══════════════════════════════════════════════════════════════════════════════

  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  ▶  BASE AMI  ·  packer build -only=cpu-ds-ml-base  ·  ~35–50 min      ║
  ╠══════════════════════════════════════════════════════════════════════════╣
  ║                                                                          ║
  ║   SOURCE  ──  Ubuntu 22.04 LTS  (Canonical  ·  ami-0*jammy-amd64)      ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~5 min   ║
  ║   │  1  APT BOOTSTRAP                                       │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  curl · jq · git-lfs · unzip · gnupg · build-essential │░          ║
  ║   │  ufw · auditd · fail2ban · chrony · unattended-upgrades │░          ║
  ║   │  openscap-scanner · trivy v0.70.0 (pinned)              │░          ║
  ║   │  awscli v2  (PGP-verified  ·  no curl|sh)               │░          ║
  ║   │  Nix 2.24.9 multi-user daemon  (pinned installer)       │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~4 min   ║
  ║   │  2  CIS HARDENING  (harden.sh)                         │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  ┌─────────────────────┐  ┌─────────────────────────┐  │░          ║
  ║   │  │  §1-2  Filesystem   │  │  §3    Network          │  │░          ║
  ║   │  │  tmpfs · modules    │  │  sysctl · UFW · sysctl  │  │░          ║
  ║   │  │  AIDE  · AppArmor   │  │  martians · SYN cookies │  │░          ║
  ║   │  └─────────────────────┘  └─────────────────────────┘  │░          ║
  ║   │  ┌─────────────────────┐  ┌─────────────────────────┐  │░          ║
  ║   │  │  §4    Logging      │  │  §5    Access           │  │░          ║
  ║   │  │  auditd  (bounded)  │  │  SSH · PAM · faillock   │  │░          ║
  ║   │  │  logrotate+maxsize  │  │  sudo · password aging  │  │░          ║
  ║   │  │  journald+keepfree  │  │  TMOUT · wheel group    │  │░          ║
  ║   │  └─────────────────────┘  └─────────────────────────┘  │░          ║
  ║   │                  114 controls  ·  0 FAIL  ·  1 WARN     │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~8 min   ║
  ║   │  3  PARALLEL NIX BUILDS  (build-base-envs.sh)          │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │                                                         │░          ║
  ║   │   py-base (3.11) ──────────────────────────────┐       │░          ║
  ║   │   py-base-py312  ──────────────────────────────┤       │░          ║
  ║   │   py-base-py313  ──────────────────────────────┤       │░          ║
  ║   │   julia          ──────────────────────────────┤ wait  │░          ║
  ║   │   R              ──────────────────────────────┤  all  │░          ║
  ║   │   go             ──────────────────────────────┤  12   │░          ║
  ║   │   java (JDK 21)  ──────────────────────────────┤       │░          ║
  ║   │   spark          ──────────────────────────────┤       │░          ║
  ║   │   rustc · cargo  ──────────────────────────────┤       │░          ║
  ║   │   nodejs 22 LTS  ──────────────────────────────┘       │░          ║
  ║   │                                                         │░          ║
  ║   │   all 12 fire simultaneously  ·  cache.nixos.org        │░          ║
  ║   │   download-bound  ·  fail-fast on any error             │░          ║
  ║   │                                                         │░          ║
  ║   │   → /opt/nix/envs/{base,base-py312,base-py313}         │░          ║
  ║   │   → /opt/nix/langs/{java,spark,julia,R,go,rustc,...}   │░          ║
  ║   │   → /usr/local/bin/{py311,py312,py313,java,go,...}     │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~1 min   ║
  ║   │  4  AMI FINALIZE  (ami-finalize.sh)                     │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │  packages.txt  ·  CycloneDX SBOM  ·  EULA  ·  MOTD    │░          ║
  ║   │  nix GC + store optimise  ·  pip cache purge           │░          ║
  ║   │  SSH host keys  ·  cloud-init clean  ·  machine-id     │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║               ╔═══════════▼══════════════════════╗                      ║
  ║               ║  ◆  BASE AMI                     ║                      ║
  ║               ║  cpu-ds-ml-ubuntu-2204-base-<ts> ║                      ║
  ║               ║  tagged  Role=dsml               ║                      ║
  ║               ╚══════════════════════════════════╝                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

                           │
                           │  data "amazon-ami" "base"
                           │  auto-discovers latest BASE AMI  ·  no duplication
                           │  of apt / hardening / Nix work  (~1.5h saved)
                           │
  ╔══════════════════════════════════════════════════════════════════════════╗
  ║  ▶  PRO AMI   ·  packer build -only=cpu-ds-ml-pro   ·  ~20–25 min      ║
  ╠══════════════════════════════════════════════════════════════════════════╣
  ║                                                                          ║
  ║   SOURCE  ──  BASE AMI  (hardened  ·  Nix envs intact  ·  all tools)   ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~18 min  ║
  ║   │  1  PARALLEL PIP INSTALLS  (build-pro-envs.sh)         │░          ║
  ║   │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │░          ║
  ║   │                                                         │░          ║
  ║   │   py311 ─► venv (--system-site-packages) ──────────┐  │░          ║
  ║   │   py312 ─► venv (--system-site-packages) ──────────┤  │░          ║
  ║   │   py313 ─► venv (--system-site-packages) ──────────┘  │░          ║
  ║   │              3 pip jobs fire simultaneously             │░          ║
  ║   │                                                         │░          ║
  ║   │   Each env installs:                                    │░          ║
  ║   │   ├─ torch · torchvision · torchaudio  (CPU ~200 MB)   │░          ║
  ║   │   ├─ tensorflow-cpu                    (CPU ~600 MB)   │░          ║
  ║   │   ├─ transformers · datasets · tokenizers · accelerate │░          ║
  ║   │   └─ mlflow · xgboost · lightgbm                       │░          ║
  ║   │                                                         │░          ║
  ║   │   inherits base: numpy · pandas · pyspark · sklearn    │░          ║
  ║   │   → /opt/nix/envs/{pro,pro-py312,pro-py313}            │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║   ┌───────────────────────▼────────────────────────────────┐  ~1 min   ║
  ║   │  2  AMI FINALIZE  (ami-finalize.sh)                     │░          ║
  ║   │  packages.txt (all 3 envs)  ·  SBOM  ·  EULA  ·  scrub │░          ║
  ║   └────────────────────────────────────────────────────────┘░          ║
  ║    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           ║
  ║                           │                                              ║
  ║               ╔═══════════▼══════════════════════╗                      ║
  ║               ║  ◆  PRO AMI                      ║                      ║
  ║               ║  cpu-ds-ml-ubuntu-2204-pro-<ts>  ║                      ║
  ║               ║  tagged  Role=dsml               ║                      ║
  ║               ╚══════════════════════════════════╝                      ║
  ╚══════════════════════════════════════════════════════════════════════════╝

  ┌──────────────────────────────────────────────────────────────────────────┐
  │  Build Summary  ·  c6i.xlarge (4 vCPU / 8 GB)  ·  Spot (~70% savings)  │
  ├─────────────────────┬──────────────────────────────┬────────────────────┤
  │  AMI                │  Wall-clock time             │  Cost at Spot      │
  ├─────────────────────┼──────────────────────────────┼────────────────────┤
  │  Base               │  ~35–50 min                  │  ~$0.04            │
  │  Pro (after base)   │  ~20–25 min                  │  ~$0.02            │
  │  Both (sequential)  │  ~55–75 min                  │  ~$0.06            │
  ├─────────────────────┴──────────────────────────────┴────────────────────┤
  │  On-demand scan: sudo ami-scan  ·  results → /var/log/ami-scan/         │
  └──────────────────────────────────────────────────────────────────────────┘
```

## Structure
- `packer.pkr.hcl` — Packer template (amazon-ebs) producing base and pro AMIs
- `nix/flake.nix` — Nix flake defining Python envs and toolchains
- `harden.sh` — OS hardening script (CIS-aligned)
- `scripts/` — helpers
  - `build-base-envs.sh` — parallel Nix builds for all base envs + toolchains
  - `build-pro-envs.sh` — parallel pip installs for pro DL packages
  - `ami-finalize.sh` — manifest, SBOM, EULA, MOTD, AMI scrub (runs last)
  - `spark-java.sh` — system profile for JAVA_HOME/SPARK_HOME/PYSPARK_PYTHON
- `examples/` — minimal PySpark examples
- `USAGE.md` — runtime usage and quick commands
- `SECURITY_REPORT.md` — hardened controls and verification steps
- `listing/` & `legal/` — marketplace listing content and license/notice templates

## Building
Prereqs: Packer with amazon plugin, AWS creds to build AMIs.

Validate and inspect:
```bash
packer init .
packer validate .
packer inspect .
```

Build base only (example):
```bash
packer build -only=cpu-ds-ml-base .
```
Build pro only (example):
```bash
packer build -only=cpu-ds-ml-pro .
```

Notes:
- Instance type defaults to `c6i.xlarge` (4 vCPU / 8 GB). Use `c6i.2xlarge` for faster builds.
- Set `spot_price = "auto"` in your vars file to cut build cost by ~70%.
- The template copies the flake and locks it in-place before building envs.
- Always build base first; the pro build auto-discovers it via `data "amazon-ami" "base"`.

## Runtime Usage (on the AMI)
See `USAGE.md` for full details. Quick checks:
```bash
py311 -V && py312 -V && py313 -V
java -version && spark-submit --version
nix flake show /opt/nix/flake
```

PySpark (choose interpreter):
```bash
# Python 3.13
PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python pyspark
# Python 3.12
PYSPARK_PYTHON=/opt/nix/envs/base-py312/bin/python pyspark
# Python 3.11
PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark
```

## Security Notes
- AIDE DB is initialized; run `sudo aide --check` to verify integrity
- UFW is active; open only the ports you need

## Customization
- Extend `nix/flake.nix` with additional packages or overlays
- Add/adjust hardening in `harden.sh` per your policies
- Add more examples under `/usr/share/examples`

## License and Notices
This distribution packages and configures upstream open-source software. See `legal/ATTRIBUTIONS.tpl.md` and `legal/NOTICE.tpl.md`. On-instance, see `/usr/share/OSS_NOTICES.md` and use the env report commands in `USAGE.md` for dependency enumeration.
# aws-amis-ml

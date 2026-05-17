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
┌─────────────────────────────────────────────────────────────────────────────┐
│  packer build -only=cpu-ds-ml-base                            ~35–50 min    │
│                                                                             │
│  Ubuntu 22.04 (Canonical AMI)                                               │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 1 · apt bootstrap                          ~5 min     │            │
│  │  curl, jq, git-lfs, unzip, awscli v2 (PGP-verified),       │            │
│  │  auditd, fail2ban, ufw, chrony, unattended-upgrades         │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 2 · CIS hardening (harden.sh)              ~2 min     │            │
│  │  114 CIS Ubuntu 22.04 L1+L2 controls, SSH, kernel sysctl,  │            │
│  │  AppArmor, auditd immutable rules, AIDE init, UFW           │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 3 · Nix daemon install                     ~2 min     │            │
│  │  Pinned installer (nix-2.24.9), multi-user daemon,         │            │
│  │  flake lock, pulls from cache.nixos.org                     │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 4 · Parallel Nix builds (build-base-envs.sh) ~8 min  │            │
│  │                                                             │            │
│  │   py-base ──┐                                              │            │
│  │   py312   ──┤                                              │            │
│  │   py313   ──┤                                              │            │
│  │   julia   ──┼──► all 12 builds fire simultaneously        │            │
│  │   R       ──┤    (download-bound, not CPU-bound)          │            │
│  │   go      ──┤    wait + fail-fast if any build errors     │            │
│  │   java    ──┤                                              │            │
│  │   spark   ──┤                                              │            │
│  │   rustc   ──┤                                              │            │
│  │   cargo   ──┤                                              │            │
│  │   nodejs  ──┘                                              │            │
│  │                                                             │            │
│  │  → /opt/nix/envs/{base,base-py312,base-py313}              │            │
│  │  → /opt/nix/langs/{java,spark,julia,R,go,rustc,cargo,node} │            │
│  │  → /usr/local/bin/{py311,py312,py313,java,spark-submit,...} │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 5 · ami-finalize.sh                        ~1 min     │            │
│  │  Package manifest, CycloneDX SBOM, EULA, MOTD,             │            │
│  │  scrub: SSH host keys, cloud-init, bash history, logs,     │            │
│  │  machine-id reset                                           │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  BASE AMI  (cpu-ds-ml-ubuntu-2204-base-<ts>)   tagged Role=dsml             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  packer build -only=cpu-ds-ml-pro              (run AFTER base) ~20–25 min  │
│                                                                             │
│  data "amazon-ami" "base"                                                   │
│  → auto-discovers latest base AMI by name + tag                             │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 1 · Parallel pip installs (build-pro-envs.sh) ~18 min │            │
│  │                                                             │            │
│  │   py311: venv --system-site-packages ──┐                   │            │
│  │   py312: venv --system-site-packages ──┼──► 3 pip jobs     │            │
│  │   py313: venv --system-site-packages ──┘   in parallel     │            │
│  │                                                             │            │
│  │   Each installs:                                            │            │
│  │     torch / torchvision / torchaudio  (CPU wheels ~200 MB) │            │
│  │     tensorflow-cpu                    (pre-built ~600 MB)  │            │
│  │     transformers / datasets / tokenizers / accelerate      │            │
│  │     mlflow / xgboost / lightgbm                            │            │
│  │                                                             │            │
│  │  → /opt/nix/envs/{pro,pro-py312,pro-py313}                 │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │  Step 2 · ami-finalize.sh                        ~1 min     │            │
│  │  Package manifest (all 3 envs), SBOM, EULA, MOTD, scrub    │            │
│  └─────────────────────────────────────────────────────────────┘            │
│         │                                                                   │
│         ▼                                                                   │
│  PRO AMI  (cpu-ds-ml-ubuntu-2204-pro-<ts>)     tagged Role=dsml             │
└─────────────────────────────────────────────────────────────────────────────┘

Build time summary (c6i.xlarge, Spot):
  Base AMI:  ~35–50 min   (apt 5 + harden 2 + Nix daemon 2 + parallel Nix 8 + finalize 1)
  Pro AMI:   ~20–25 min   (parallel pip 18 + finalize 1, skips all base work)
  Total:     ~55–75 min   (sequential) or ~35–50 min (base + pro overlap if Spot available)

Cost estimate at Spot (~$0.05/hr for c6i.xlarge):
  Base:  ~$0.04    Pro:  ~$0.02    Total: ~$0.06 per full build cycle
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

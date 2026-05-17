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

## Structure
- `packer.pkr.hcl` — Packer template (amazon-ebs) producing base and pro AMIs
- `nix/flake.nix` — Nix flake defining Python envs and toolchains
- `harden.sh` — OS hardening script (CIS-aligned)
- `scripts/` — helpers
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
- Instance type defaults to `m6i.large` for builds.
- The template copies the flake and locks it in-place before building envs.

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

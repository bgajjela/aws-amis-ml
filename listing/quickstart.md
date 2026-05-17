Quick Start (CPU DS/ML AMI)

Launch
- Instance type: m6i.large recommended for build/runtime balance
- AMI includes hardened Ubuntu 22.04, Nix-managed runtimes, and audited defaults (see SECURITY_REPORT.md)
- Security Group: allow only SSH (22) from your IP; open additional ports only as required

First login checks
- py311/py313: `py311 -V && py313 -V`
- Lang toolchains: `julia -e 'println(VERSION)' && R --version && go version`
- Java/Spark: `java -version && spark-submit --version`
- Nix: `nix --version && nix flake show /opt/nix/flake`

PySpark
- Python 3.11: `PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark`
- Python 3.13: `PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python pyspark`

Rebuild envs (optional)
- Lock flake: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix flake lock /opt/nix/flake'`
- Rebuild base: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/base /opt/nix/flake#py-base'`

Security posture
- SSH hardened (no passwords/root), UFW default deny inbound with rate-limited SSH
- CIS-aligned sysctl, AIDE, AppArmor, audit rules, log compression/rotation, tmpfs mounts (/tmp, /var/tmp)


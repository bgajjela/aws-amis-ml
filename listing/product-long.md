Why This AMI
- Ready-to-use CPU data science/ML environment with reproducible Nix builds.
- Security-first: CIS-aligned hardening, UFW locked down, AppArmor/AIDE/auditd configured.
- Faster onboarding: Python (3.11, 3.13), Julia, R, Go, Java 17, Spark, plus curated DS/ML/AI packages.

What’s Included
- Ubuntu 22.04 LTS (HVM, EBS, gp3)
- Nix-managed environments under `/opt/nix` with symlinks in `/usr/local/bin`
- Python envs: base and pro (plus 3.13 variants) with common DS/ML libs (numpy, pandas, scikit-learn, pyarrow, polars, matplotlib, seaborn, onnxruntime, OpenCV, etc.). Pro adds deep learning stacks (PyTorch, TensorFlow, XGBoost/LightGBM/CatBoost, transformers).
- Toolchains: Julia, R, Go, Java 17 (OpenJDK), Apache Spark (spark-submit and pyspark)

Security & Compliance
- SSH: key-only, root login disabled, strong crypto, login banner
- Firewall: UFW default deny inbound; SSH allowed and rate-limited
- System: CIS networking sysctl, tmpfs for /tmp and /var/tmp (nodev,nosuid,noexec), hardened /dev/shm
- Auditing: auditd immutable rules; AppArmor enforcing; AIDE initialized; logrotate + journald compression and caps
- Ulimits: higher defaults for login shells and systemd services

Operations
- Rebuild envs via `nix build` from `/opt/nix/flake`; lock revisions with `nix flake lock`
- PySpark with specific Python: set `PYSPARK_PYTHON` to the desired interpreter
- Add your own Nix overlays or flake inputs to extend packages

Support
- Basic usage documented in `USAGE.md`; security details in `SECURITY_REPORT.md`
- Contact seller for customizations (VPC/subnet/SG guidance, additional hardening, GPU images)


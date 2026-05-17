Nix-based Language Environments (CPU DS/ML AMIs)

Overview
- These AMIs include Nix and prebuilt environments for Python (3.11 and 3.13), plus Julia, R, and Go.
- All Nix realizations live under `/opt/nix`. The Nix daemon is enabled and shells source `/nix/.../nix-daemon.sh` automatically.

Prebuilt Locations
- Python envs (requirements-based):
  - Python 3.11 base: `/opt/nix/envs/base`
  - Python 3.11 pro: `/opt/nix/envs/pro`
  - Python 3.12 base: `/opt/nix/envs/base-py312`
  - Python 3.12 pro: `/opt/nix/envs/pro-py312`
  - Python 3.13 base: `/opt/nix/envs/base-py313`
  - Python 3.13 pro: `/opt/nix/envs/pro-py313`
- Toolchains:
  - Python 3.13 interpreter: `/opt/nix/langs/python313`
  - Julia: `/opt/nix/langs/julia`
  - R: `/opt/nix/langs/R`
  - Go: `/opt/nix/langs/go`
  - Java 17 (OpenJDK): `/opt/nix/langs/java`
  - Apache Spark: `/opt/nix/langs/spark`

Convenience Binaries
- Symlinks are created in `/usr/local/bin`:
  - Python 3.11 env: `py311`
  - Python 3.12 env: `py312`
  - Python 3.13 env: `py313`
  - Julia: `julia`
  - R: `R`, `Rscript`
  - Go: `go`
  - Java: `java`
  - Spark: `spark-submit`, `pyspark`

Quick Start
- Python 3.11 env: `py311 -V` then `py311 -c "import numpy as np; print(np.__version__)"`
- Python 3.12 env: `py312 -V`
- Python 3.13 env: `py313 -V`
- Julia: `julia -e 'println(VERSION)'`
- R: `R --version` or `Rscript -e 'print(R.version.string)'`
- Go: `go version`
 - Java: `java -version`
 - Spark: `spark-submit --version`

Spark/PySpark Quick Commands (copy/paste)
- Set environment (once per shell):
  - `export JAVA_HOME=/opt/nix/langs/java`
  - `export SPARK_HOME=/opt/nix/langs/spark`
  - `export PATH="$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH"`
- PySpark with Python 3.13:
  - `PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python pyspark`
- PySpark with Python 3.12:
  - `PYSPARK_PYTHON=/opt/nix/envs/base-py312/bin/python pyspark`
- PySpark with Python 3.11:
  - `PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark`
- Run examples (Python 3.13):
  - `cd /usr/share/examples/spark && PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python spark-submit pyspark_basic.py`
  - `cd /usr/share/examples/spark && PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python spark-submit pyspark_pi.py`
- Java: `java -version`
- Spark: `spark-submit --version`

Using Envs Directly (without symlinks)
- Python 3.11 base env: `/opt/nix/envs/base/bin/python`
- Python 3.12 base env: `/opt/nix/envs/base-py312/bin/python` (or `python3.12`)
- Python 3.13 base env: `/opt/nix/envs/base-py313/bin/python` (or `python3.13`)
- Julia: `/opt/nix/langs/julia/bin/julia`
- R: `/opt/nix/langs/R/bin/R` and `/opt/nix/langs/R/bin/Rscript`
- Go: `/opt/nix/langs/go/bin/go`

Flake Source and Rebuilding
- Flake path on the AMI: `/opt/nix/flake/flake.nix` (packages are defined in the flake; no external requirements files).
- Lock the flake (pins versions): `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix flake lock /opt/nix/flake'`
- Rebuild an env (requires network):
  - Base 3.11: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/base /opt/nix/flake#py-base'`
  - Base 3.12: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/base-py312 /opt/nix/flake#py-base-py312'`
  - Base 3.13: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/base-py313 /opt/nix/flake#py-base-py313'`
  - Pro 3.11: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/pro /opt/nix/flake#py-pro'`
  - Pro 3.12: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/pro-py312 /opt/nix/flake#py-pro-py312'`
  - Pro 3.13: `sudo -E bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/pro-py313 /opt/nix/flake#py-pro-py313'`

Audit Installed Packages
- Base: `nix run /opt/nix/flake#env-report-base`
- Pro: `nix run /opt/nix/flake#env-report-pro`

Notes on Python Versions
- Python minor versions are exact (3.11 vs 3.13). Micro versions (e.g., 3.13.5 vs 3.13.7) depend on the nixpkgs revision pinned in the flake.
- If you require a specific micro version, use an overlay or pyenv via Nix; reach out for a pinned overlay example.

Using Nix Shells and Apps
- Ad-hoc shell with Python 3.13: `nix shell /opt/nix/flake#python313 -c python3.13 -V`
- Run binaries from env without modifying PATH: `nix run /opt/nix/flake#py-base --command python -V`
- Inspect flake outputs: `nix flake show /opt/nix/flake`

Environment Variables
- The image sources Nix profile (`/etc/profile.d/nix.sh`) for all shells.
- To set tokens or runtime env, use shell exports or systemd units (not included by default in this image).
 - Spark/Java profile: `/etc/profile.d/spark-java.sh` sets `JAVA_HOME`, `SPARK_HOME`, PATH, and defaults `PYSPARK_PYTHON` to Python 3.13. Override per-session if needed.

Examples
- Minimal PySpark examples are installed under `/usr/share/examples/spark/`:
  - `pyspark_basic.py`: creates a SparkSession, simple RDD/DataFrame ops
  - `pyspark_pi.py`: approximate Pi using RDD operations

Support
- If packages fail to resolve in mach-nix (especially scientific wheels), we can add overrides in the flake to point to alternative builds or lower Python.

PySpark and Spark Notes
- Choose Python interpreter for PySpark explicitly when needed:
  - Use Python 3.11 env: `PYSPARK_PYTHON=/opt/nix/envs/base/bin/python pyspark`
  - Use Python 3.13 env: `PYSPARK_PYTHON=/opt/nix/envs/base-py313/bin/python pyspark`
- Environment variables (optional):
  - `export JAVA_HOME=/opt/nix/langs/java`
  - `export SPARK_HOME=/opt/nix/langs/spark`
  - `export PATH="$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH"` (symlinks already exist under `/usr/local/bin`)
- Troubleshooting:
  - If PySpark cannot find Java, export `JAVA_HOME` as above and retry.
  - When using Python 3.13 with third-party libs, prefer `base-py313` or `pro-py313` envs for wheel compatibility.
  - For Hadoop or external connectors, set `HADOOP_CONF_DIR` and place required jars under `$SPARK_HOME/jars`.

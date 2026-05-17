#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: run-provision.sh <common|base|pro>

  common  Run steps shared by both AMI variants (harden, prep Nix, copy files)
  base    Build the base Python environments and runtimes via Nix
  pro     Build the pro Python environments (includes mlflow) and runtimes
USAGE
}

source_nix() {
  # shellcheck disable=SC1091
  if [ -s /root/.nix-profile/etc/profile.d/nix.sh ]; then
    # shellcheck disable=SC1090
    . /root/.nix-profile/etc/profile.d/nix.sh
  elif [ -s /etc/profile.d/nix.sh ]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/nix.sh
  else
    echo "nix profile script not found" >&2
    return 1
  fi
}

ensure_profile_script() {
  if [ -f /root/.nix-profile/etc/profile.d/nix.sh ] && [ ! -f /etc/profile.d/nix.sh ]; then
    install -D -m 0644 /root/.nix-profile/etc/profile.d/nix.sh /etc/profile.d/nix.sh
  fi
}

link_if_exec() {
  local target=$1
  local link_name=$2
  if [ -x "$target" ]; then
    ln -sf "$target" "$link_name"
  elif compgen -G "${target}3.*" >/dev/null 2>&1; then
    # Handle python3.x-style binaries under env/bin
    ln -sf "$(compgen -G "${target}3.*" | head -n1)" "$link_name"
  fi
}

smoke_python_variant() {
  local binary=$1
  "$binary" -V
  "$binary" -c 'import pyspark; print(pyspark.__version__)'
}

command=${1:-}
if [ -z "$command" ]; then
  usage
  exit 1
fi

case "$command" in
  common)
    python3 -m venv /opt/venvs/py311
    chmod 0755 /opt/venvs/py311

    chmod +x /tmp/harden.sh
    /tmp/harden.sh

    install -D -m 0644 /tmp/spark-java.sh /etc/profile.d/spark-java.sh

    mkdir -p /opt/nix/flake /opt/nix/envs /opt/nix/langs
    if [ -f /tmp/flake.nix ]; then
      mv /tmp/flake.nix /opt/nix/flake/flake.nix
    fi

    ensure_profile_script
    source_nix
    nix flake lock /opt/nix/flake
    ;;

  base|pro)
    ensure_profile_script
    source_nix

    case "$command" in
      base)
        nix build -o /opt/nix/envs/base-py312 /opt/nix/flake#py-base-py312
        nix build -o /opt/nix/envs/base /opt/nix/flake#py-base
        nix build -o /opt/nix/envs/base-py313 /opt/nix/flake#py-base-py313
        env311=/opt/nix/envs/base
        env312=/opt/nix/envs/base-py312
        env313=/opt/nix/envs/base-py313
        build_tag="1.0.0-BASE"
        ;;
      pro)
        nix build -o /opt/nix/envs/pro-py312 /opt/nix/flake#py-pro-py312
        nix build -o /opt/nix/envs/pro /opt/nix/flake#py-pro
        nix build -o /opt/nix/envs/pro-py313 /opt/nix/flake#py-pro-py313
        env311=/opt/nix/envs/pro
        env312=/opt/nix/envs/pro-py312
        env313=/opt/nix/envs/pro-py313
        build_tag="1.0.0-PRO"
        ;;
    esac

    nix build -o /opt/nix/langs/python313 /opt/nix/flake#python313
    nix build -o /opt/nix/langs/julia /opt/nix/flake#julia
    nix build -o /opt/nix/langs/R /opt/nix/flake#R
    nix build -o /opt/nix/langs/go /opt/nix/flake#go
    nix build -o /opt/nix/langs/java /opt/nix/flake#java
    nix build -o /opt/nix/langs/spark /opt/nix/flake#spark

    link_if_exec "${env311}/bin/python" /usr/local/bin/py311
    link_if_exec "${env312}/bin/python" /usr/local/bin/py312
    link_if_exec "${env313}/bin/python" /usr/local/bin/py313
    link_if_exec /opt/nix/langs/julia/bin/julia /usr/local/bin/julia
    link_if_exec /opt/nix/langs/R/bin/R /usr/local/bin/R
    link_if_exec /opt/nix/langs/R/bin/Rscript /usr/local/bin/Rscript
    link_if_exec /opt/nix/langs/go/bin/go /usr/local/bin/go
    link_if_exec /opt/nix/langs/java/bin/java /usr/local/bin/java
    link_if_exec /opt/nix/langs/spark/bin/spark-submit /usr/local/bin/spark-submit
    link_if_exec /opt/nix/langs/spark/bin/pyspark /usr/local/bin/pyspark

    install -d -m 0755 /usr/share/examples/spark
    if [ -f /tmp/pyspark_basic.py ]; then
      mv /tmp/pyspark_basic.py /usr/share/examples/spark/pyspark_basic.py
    fi
    if [ -f /tmp/pyspark_pi.py ]; then
      mv /tmp/pyspark_pi.py /usr/share/examples/spark/pyspark_pi.py
    fi
    chmod 0644 /usr/share/examples/spark/pyspark_*.py

    nix --version
    smoke_python_variant /usr/local/bin/py311
    smoke_python_variant /usr/local/bin/py312
    smoke_python_variant /usr/local/bin/py313

    if [ "$command" = "pro" ]; then
      /usr/local/bin/py311 -c 'import mlflow; print(mlflow.__version__)'
    fi

    java -version
    spark-submit --version
    julia -e 'println(VERSION)'
    R --version
    go version

    printf 'VERSION=%s\n' "$build_tag" > /usr/share/BUILD_INFO
    ;;

  *)
    usage
    exit 1
    ;;
esac

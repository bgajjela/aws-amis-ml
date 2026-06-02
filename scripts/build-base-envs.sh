#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Dimenpoint
# build-base-envs.sh — parallel Nix builds for the cache-friendly core Python
# envs plus language toolchains, then layered pip-wheel installs for the heavy
# notebook / computer-vision packages. This keeps the final AMI Python paths
# unchanged while avoiding very slow Nix closure builds for packages like
# onnxruntime, OpenCV, and scikit-image.
set -euo pipefail

FLAKE="/opt/nix/flake"
ENVS="/opt/nix/envs"
CACHE_ENVS="/opt/nix/cache-envs"
LANGS="/opt/nix/langs"
ARCH="$(uname -m)"

sudo mkdir -p "${ENVS}" "${CACHE_ENVS}" "${LANGS}"

# ── Background helper ─────────────────────────────────────────────────────────
# Logs per-build to /tmp/nix-<label>.log so output doesn't interleave.
# Caller captures $! right after each call.

_nix_bg() {
  local label="$1" out="$2" attr="$3"
  local log="/tmp/nix-${label}.log"
  # Redirect inside the sudo command so root writes the log file under /tmp.
  sudo bash -lc \
    "source /etc/profile.d/nix.sh && \
     nix build --extra-experimental-features nix-command --extra-experimental-features flakes --max-jobs auto --cores 0 -o ${out} ${FLAKE}#${attr} \
     >\"${log}\" 2>&1" &
}

# ── Launch all builds in parallel ────────────────────────────────────────────
echo "=== Launching parallel Nix cache builds ==="

_nix_bg "py-base"     "${CACHE_ENVS}/base"       "py-cache-base"       ; PID_py_base=$!
_nix_bg "py-base-312" "${CACHE_ENVS}/base-py312" "py-cache-base-py312" ; PID_py312=$!
_nix_bg "py-base-313" "${CACHE_ENVS}/base-py313" "py-cache-base-py313" ; PID_py313=$!
_nix_bg "python313"   "${LANGS}/python313"  "python313"     ; PID_py313_lang=$!
_nix_bg "julia"       "${LANGS}/julia"      "julia"         ; PID_julia=$!
_nix_bg "R"           "${LANGS}/R"          "R"             ; PID_R=$!
_nix_bg "go"          "${LANGS}/go"         "go"            ; PID_go=$!
_nix_bg "java"        "${LANGS}/java"       "java"          ; PID_java=$!
_nix_bg "spark"       "${LANGS}/spark"      "spark"         ; PID_spark=$!
_nix_bg "rustc"       "${LANGS}/rustc"      "rustc"         ; PID_rustc=$!
_nix_bg "cargo"       "${LANGS}/cargo"      "cargo"         ; PID_cargo=$!
_nix_bg "nodejs"      "${LANGS}/nodejs"     "nodejs"        ; PID_nodejs=$!

echo "  All 12 builds started — waiting (mostly downloading from cache.nixos.org)..."
echo ""

# ── Collect results ───────────────────────────────────────────────────────────
FAILED=0

_wait() {
  local label="$1" pid="$2"
  if wait "${pid}"; then
    echo "  [ok]   ${label}"
  else
    echo "  [FAIL] ${label} — log: /tmp/nix-${label}.log"
    cat "/tmp/nix-${label}.log"
    FAILED=1
  fi
}

_wait "py-base"     "${PID_py_base}"
_wait "py-base-312" "${PID_py312}"
_wait "py-base-313" "${PID_py313}"
_wait "python313"   "${PID_py313_lang}"
_wait "julia"       "${PID_julia}"
_wait "R"           "${PID_R}"
_wait "go"          "${PID_go}"
_wait "java"        "${PID_java}"
_wait "spark"       "${PID_spark}"
_wait "rustc"       "${PID_rustc}"
_wait "cargo"       "${PID_cargo}"
_wait "nodejs"      "${PID_nodejs}"

if [[ "${FAILED}" -ne 0 ]]; then
  echo ""
  echo "ERROR: One or more Nix builds failed (see logs above)."
  exit 1
fi

# ── Layer heavy wheels on top of the cached Nix envs ─────────────────────────
_layer_base() {
  local label="$1" cache_env="$2" final_env="$3"
  echo "=== [${label}] layering wheels onto ${final_env} (arch: ${ARCH}) ==="

  sudo rm -rf "${final_env}"
  sudo "${cache_env}/bin/python" -m venv --system-site-packages "${final_env}"
  sudo "${final_env}/bin/pip" install --upgrade pip --quiet

  echo "  [${label}] jupyterlab + vision/runtime + polars wheels..."
  sudo "${final_env}/bin/pip" install \
    jupyterlab \
    onnxruntime \
    opencv-python \
    scikit-image \
    polars \
    --quiet

  echo "  [${label}] smoke test..."
  "${final_env}/bin/python" -c "
import numpy, pandas, pyspark, sklearn, polars
import jupyterlab, onnxruntime, cv2, skimage
print('  numpy=' + numpy.__version__ + ' polars=' + polars.__version__ + \
      ' jupyterlab=' + jupyterlab.__version__ + ' onnxruntime=' + onnxruntime.__version__)
"
  echo "=== [${label}] DONE ==="
}

echo ""
echo "=== Layering heavy Python wheels in parallel ==="

_layer_base "py311" "${CACHE_ENVS}/base" /opt/nix/envs/base >"/tmp/base-py311.log" 2>&1 &
PID_layer_311=$!

_layer_base "py312" "${CACHE_ENVS}/base-py312" /opt/nix/envs/base-py312 >"/tmp/base-py312.log" 2>&1 &
PID_layer_312=$!

_layer_base "py313" "${CACHE_ENVS}/base-py313" /opt/nix/envs/base-py313 >"/tmp/base-py313.log" 2>&1 &
PID_layer_313=$!

FAILED_LAYER=0

_wait_layer() {
  local label="$1" pid="$2" log="$3"
  if wait "${pid}"; then
    echo "  [ok]   ${label}"
    cat "${log}"
  else
    echo "  [FAIL] ${label} — log below:"
    cat "${log}"
    FAILED_LAYER=1
  fi
}

_wait_layer "py311" "${PID_layer_311}" /tmp/base-py311.log
_wait_layer "py312" "${PID_layer_312}" /tmp/base-py312.log
_wait_layer "py313" "${PID_layer_313}" /tmp/base-py313.log

if [[ "${FAILED_LAYER}" -ne 0 ]]; then
  echo ""
  echo "ERROR: One or more layered base env builds failed (see logs above)."
  exit 1
fi

# ── Symlinks ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Creating /usr/local/bin symlinks ==="

_link() {
  local src="$1" dst="$2"
  if [[ -x "${src}" ]]; then
    sudo ln -sf "${src}" "${dst}"
    echo "  ${dst} -> ${src}"
  else
    echo "  WARN: ${src} not found — skipping ${dst}"
  fi
}

_link "${ENVS}/base/bin/python"         /usr/local/bin/py311

# py312/py313: Nix may expose the binary as python3.12 / python3.13 rather than python
for ver in 312 313; do
  env_path="${ENVS}/base-py${ver}"
  dst="/usr/local/bin/py${ver}"
  if [[ -x "${env_path}/bin/python" ]]; then
    sudo ln -sf "${env_path}/bin/python" "${dst}"
    echo "  ${dst} -> ${env_path}/bin/python"
  else
    versioned="$(ls "${env_path}/bin/python3."* 2>/dev/null | head -n1)"
    if [[ -n "${versioned}" ]]; then
      sudo ln -sf "${versioned}" "${dst}"
      echo "  ${dst} -> ${versioned}"
    else
      echo "  WARN: no python binary found in ${env_path}/bin — skipping ${dst}"
    fi
  fi
done

_link "${LANGS}/julia/bin/julia"         /usr/local/bin/julia
_link "${LANGS}/R/bin/R"                 /usr/local/bin/R
_link "${LANGS}/R/bin/Rscript"           /usr/local/bin/Rscript
_link "${LANGS}/go/bin/go"               /usr/local/bin/go
_link "${LANGS}/java/bin/java"           /usr/local/bin/java
_link "${LANGS}/rustc/bin/rustc"         /usr/local/bin/rustc
_link "${LANGS}/cargo/bin/cargo"         /usr/local/bin/cargo
_link "${LANGS}/nodejs/bin/node"         /usr/local/bin/node
_link "${LANGS}/nodejs/bin/npm"          /usr/local/bin/npm

# ── Spark wrapper scripts ─────────────────────────────────────────────────────
# Wrappers rather than symlinks so JAVA_HOME, SPARK_HOME, SPARK_LOCAL_DIRS, and
# PYSPARK_PYTHON are always set regardless of shell type (scripts, cron, ssh
# non-interactive, Jupyter kernels, systemd services). Profile.d is login-shell-only.

echo ""
echo "=== Creating Spark wrapper scripts ==="

# spark-submit: always has SPARK_HOME + JAVA_HOME in env
sudo tee /usr/local/bin/spark-submit >/dev/null <<WRAPPER
#!/bin/sh
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
export JAVA_HOME SPARK_HOME SPARK_LOCAL_DIRS
exec "\${SPARK_HOME}/bin/spark-submit" "\$@"
WRAPPER
sudo chmod 755 /usr/local/bin/spark-submit
echo "  /usr/local/bin/spark-submit (wrapper)"

# pyspark: defaults PYSPARK_PYTHON to base env but honours caller override
sudo tee /usr/local/bin/pyspark >/dev/null <<WRAPPER
#!/bin/sh
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
PYSPARK_PYTHON=\${PYSPARK_PYTHON:-/opt/nix/envs/base/bin/python}
export JAVA_HOME SPARK_HOME SPARK_LOCAL_DIRS PYSPARK_PYTHON
exec "\${SPARK_HOME}/bin/pyspark" "\$@"
WRAPPER
sudo chmod 755 /usr/local/bin/pyspark
echo "  /usr/local/bin/pyspark (wrapper, default py311)"

# pyspark311/312/313: version-pinned wrappers — work in scripts, cron, ssh, Jupyter
for ver_env in "311:/opt/nix/envs/base" "312:/opt/nix/envs/base-py312" "313:/opt/nix/envs/base-py313"; do
  ver="${ver_env%%:*}"
  env_path="${ver_env##*:}"
  sudo tee "/usr/local/bin/pyspark${ver}" >/dev/null <<WRAPPER
#!/bin/sh
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
PYSPARK_PYTHON=${env_path}/bin/python
export JAVA_HOME SPARK_HOME SPARK_LOCAL_DIRS PYSPARK_PYTHON
exec "\${SPARK_HOME}/bin/pyspark" "\$@"
WRAPPER
  sudo chmod 755 "/usr/local/bin/pyspark${ver}"
  echo "  /usr/local/bin/pyspark${ver} -> ${env_path}"
done

echo ""
echo "=== Installing newenv helper ==="

# newenv: creates a user-owned venv layered on a Nix base env so customers
# can pip install packages without touching the immutable system envs.
# Usage: newenv py311 ~/myproject   → creates ~/myproject with py311 packages
#        newenv py312 ./analysis
sudo tee /usr/local/bin/newenv >/dev/null <<'SCRIPT'
#!/bin/sh
set -e
PYVER="${1:-py311}"
DEST="${2:-.venv}"

case "${PYVER}" in
  py311) BASE=/opt/nix/envs/base        ;;
  py312) BASE=/opt/nix/envs/base-py312  ;;
  py313) BASE=/opt/nix/envs/base-py313  ;;
  pro311) BASE=/opt/nix/envs/pro        ;;
  pro312) BASE=/opt/nix/envs/pro-py312  ;;
  pro313) BASE=/opt/nix/envs/pro-py313  ;;
  *)
    echo "Usage: newenv <py311|py312|py313|pro311|pro312|pro313> [dest-dir]"
    echo "  Creates a venv layered on the chosen Nix env so you can pip install freely."
    exit 1
    ;;
esac

if [ ! -d "${BASE}" ]; then
  echo "Error: base env not found at ${BASE}" >&2
  exit 1
fi

echo "Creating venv at ${DEST} (base: ${BASE})"
"${BASE}/bin/python" -m venv --system-site-packages "${DEST}"
"${DEST}/bin/pip" install --upgrade pip --quiet
echo ""
echo "Done. Activate with:"
echo "  source ${DEST}/bin/activate"
echo ""
echo "Then pip install freely:"
echo "  pip install your-package"
SCRIPT
sudo chmod 755 /usr/local/bin/newenv
echo "  /usr/local/bin/newenv (helper to create user venvs)"

echo ""
echo "Base envs built and linked successfully."

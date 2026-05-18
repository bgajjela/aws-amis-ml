#!/usr/bin/env bash
# build-pro-envs.sh — creates pro Python envs layered on top of the base Nix envs.
#
# Strategy: venv --system-site-packages inherits base packages (numpy, pandas,
# pyspark, scikit-learn, etc.) from the immutable Nix env, then pip installs
# the heavy DL packages via pre-built CPU wheels. This is 10-20x faster than
# Nix compiling torch/tensorflow from source.
#
# All three Python versions run in parallel: ~15-20 min total (was ~45-60 min
# sequential).
#
# x86_64: PyTorch CPU from the WHL index (~200 MB/version, no CUDA overhead).
# aarch64: PyPI directly — the WHL index has incomplete ARM64 coverage for
#   torchvision/torchaudio; --index-url would replace PyPI and silently fail.
#   PyPI hosts first-class aarch64 wheels for all packages since PyTorch 2.1+.
# tensorflow-cpu: PyPI on both arches (unified package since TF 2.16; the
#   -cpu suffix is a metapackage alias that works on both x86_64 and aarch64).
set -euo pipefail

TORCH_INDEX="https://download.pytorch.org/whl/cpu"
ARCH="$(uname -m)"   # x86_64 or aarch64

# ── Per-version build function (runs in a subshell background job) ────────────
_build_pro() {
  local label="$1" base_env="$2" pro_env="$3" symlink="$4"

  echo "=== [${label}] ${base_env} -> ${pro_env} (arch: ${ARCH}) ==="

  sudo "${base_env}/bin/python" -m venv --system-site-packages "${pro_env}"
  sudo "${pro_env}/bin/pip" install --upgrade pip --quiet

  echo "  [${label}] torch (CPU wheels)..."
  if [ "${ARCH}" = "x86_64" ]; then
    # WHL index: smaller download, no CUDA wheels pulled in
    sudo "${pro_env}/bin/pip" install \
      torch torchvision torchaudio \
      --index-url "${TORCH_INDEX}" \
      --quiet
  else
    # ARM64: PyPI has first-class aarch64 wheels; WHL index coverage is incomplete
    sudo "${pro_env}/bin/pip" install \
      torch torchvision torchaudio \
      --quiet
  fi

  echo "  [${label}] tensorflow-cpu + ecosystem..."
  sudo "${pro_env}/bin/pip" install \
    tensorflow-cpu \
    transformers datasets tokenizers sentencepiece accelerate \
    --quiet

  echo "  [${label}] mlflow, xgboost, lightgbm..."
  sudo "${pro_env}/bin/pip" install mlflow xgboost lightgbm --quiet

  echo "  [${label}] smoke test..."
  "${pro_env}/bin/python" -c "
import numpy, pandas, pyspark, sklearn
import torch, tensorflow, transformers, mlflow, xgboost, lightgbm
print('  numpy=' + numpy.__version__ + ' torch=' + torch.__version__ + \
      ' tf=' + tensorflow.__version__ + ' mlflow=' + mlflow.__version__)
"
  sudo ln -sf "${pro_env}/bin/python" "${symlink}"
  echo "  [${label}] linked: ${symlink} -> ${pro_env}/bin/python"
  echo "=== [${label}] DONE ==="
}

# ── Launch all three versions in parallel ─────────────────────────────────────
echo "=== Building pro envs in parallel (py311 / py312 / py313) ==="

_build_pro "py311" /opt/nix/envs/base       /opt/nix/envs/pro       /usr/local/bin/py311 \
  >"/tmp/pro-py311.log" 2>&1 &
PID311=$!

_build_pro "py312" /opt/nix/envs/base-py312 /opt/nix/envs/pro-py312 /usr/local/bin/py312 \
  >"/tmp/pro-py312.log" 2>&1 &
PID312=$!

_build_pro "py313" /opt/nix/envs/base-py313 /opt/nix/envs/pro-py313 /usr/local/bin/py313 \
  >"/tmp/pro-py313.log" 2>&1 &
PID313=$!

echo "  py311 pid=${PID311}  py312 pid=${PID312}  py313 pid=${PID313}"
echo "  Waiting (mostly downloading wheels from PyPI / pytorch.org)..."
echo ""

# ── Collect results ───────────────────────────────────────────────────────────
FAILED=0

_wait_pro() {
  local label="$1" pid="$2" log="$3"
  if wait "${pid}"; then
    echo "  [ok]   ${label}"
    cat "${log}"
  else
    echo "  [FAIL] ${label} — log below:"
    cat "${log}"
    FAILED=1
  fi
}

_wait_pro "py311" "${PID311}" /tmp/pro-py311.log
_wait_pro "py312" "${PID312}" /tmp/pro-py312.log
_wait_pro "py313" "${PID313}" /tmp/pro-py313.log

if [[ "${FAILED}" -ne 0 ]]; then
  echo ""
  echo "ERROR: One or more pro env builds failed (see logs above)."
  exit 1
fi

echo ""
echo "=== Updating pyspark wrapper scripts to point to pro envs ==="

# Overwrite the base-env wrappers created by build-base-envs.sh so that
# pyspark311/312/313 use the pro venvs (torch/tf/transformers included).
# pyspark (bare) also updated to default to pro env.
for ver_env in "311:/opt/nix/envs/pro" "312:/opt/nix/envs/pro-py312" "313:/opt/nix/envs/pro-py313"; do
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

# Bare pyspark defaults to pro py311 env on the pro AMI
sudo tee /usr/local/bin/pyspark >/dev/null <<WRAPPER
#!/bin/sh
JAVA_HOME=/opt/nix/langs/java
SPARK_HOME=/opt/nix/langs/spark
SPARK_LOCAL_DIRS=/opt/spark-local
PYSPARK_PYTHON=\${PYSPARK_PYTHON:-/opt/nix/envs/pro/bin/python}
export JAVA_HOME SPARK_HOME SPARK_LOCAL_DIRS PYSPARK_PYTHON
exec "\${SPARK_HOME}/bin/pyspark" "\$@"
WRAPPER
sudo chmod 755 /usr/local/bin/pyspark
echo "  /usr/local/bin/pyspark (default -> pro py311)"

echo ""
echo "Pro envs built successfully."

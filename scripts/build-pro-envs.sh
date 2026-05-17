#!/usr/bin/env bash
# build-pro-envs.sh — creates pro Python envs layered on top of the base Nix envs.
#
# Strategy: venv --system-site-packages inherits base packages (numpy, pandas,
# pyspark, scikit-learn, etc.) from the immutable Nix env, then pip installs
# the heavy DL packages via pre-built CPU wheels. This is 10-20x faster than
# Nix compiling torch/tensorflow from source.
#
# Torch CPU index:    https://download.pytorch.org/whl/cpu
# tensorflow-cpu:     ~600 MB pre-built wheel (vs hours of Nix compilation)
# torch CPU:          ~200 MB per wheel (vs ~6 GB Nix CUDA closure)
set -euo pipefail

TORCH_INDEX="https://download.pytorch.org/whl/cpu"

# suffix -> base env path -> pro env path -> /usr/local/bin symlink
declare -A ENVS
ENVS[""]="/opt/nix/envs/base:/opt/nix/envs/pro:/usr/local/bin/py311"
ENVS["-py312"]="/opt/nix/envs/base-py312:/opt/nix/envs/pro-py312:/usr/local/bin/py312"
ENVS["-py313"]="/opt/nix/envs/base-py313:/opt/nix/envs/pro-py313:/usr/local/bin/py313"

for suffix in "" "-py312" "-py313"; do
  IFS=: read -r base_env pro_env symlink <<< "${ENVS[$suffix]}"
  echo ""
  echo "=== Building pro${suffix} (${base_env} -> ${pro_env}) ==="

  # Create mutable venv inheriting all base Nix packages
  sudo "$base_env/bin/python" -m venv --system-site-packages "$pro_env"
  sudo "$pro_env/bin/pip" install --upgrade pip --quiet

  # PyTorch CPU wheels — significantly smaller than CUDA builds; correct for CPU AMI
  echo "  Installing torch stack (CPU wheels)..."
  sudo "$pro_env/bin/pip" install \
    torch torchvision torchaudio \
    --index-url "$TORCH_INDEX" \
    --quiet

  # TensorFlow CPU + DL ecosystem
  echo "  Installing tensorflow-cpu and ecosystem..."
  sudo "$pro_env/bin/pip" install \
    tensorflow-cpu \
    transformers datasets tokenizers sentencepiece accelerate \
    --quiet

  # mlflow/xgboost/lightgbm: fast compiles, keep via pip for consistency
  echo "  Installing mlflow, xgboost, lightgbm..."
  sudo "$pro_env/bin/pip" install \
    mlflow xgboost lightgbm \
    --quiet

  # Smoke test: verify inherited base packages + new DL packages all import
  echo "  Smoke testing..."
  "$pro_env/bin/python" -c "
import numpy, pandas, pyspark, sklearn
import torch, tensorflow, transformers, mlflow, xgboost, lightgbm
print(f'    numpy={numpy.__version__} torch={torch.__version__} '
      f'tf={tensorflow.__version__} mlflow={mlflow.__version__}')
"

  # Update symlink to point to the pro env
  sudo ln -sf "$pro_env/bin/python" "$symlink"
  echo "  Linked: $symlink -> $pro_env/bin/python"
done

echo ""
echo "Pro envs built successfully."

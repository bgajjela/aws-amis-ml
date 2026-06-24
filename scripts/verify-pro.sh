#!/usr/bin/env bash
# verify-pro.sh — test all expected packages on a pro AMI instance.
# Creates and populates pro envs if missing, then verifies everything.
# Run: sudo bash verify-pro.sh
set -euo pipefail

ARCH="$(uname -m)"
PASS=0
FAIL=0
FIXED=0
TORCH_INDEX="https://download.pytorch.org/whl/cpu"

_ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
_fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
_fix()  { echo "  [FIX]  $*"; FIXED=$((FIXED+1)); }
_hdr()  { echo ""; echo "=== $* ==="; }

_write_pro_wrapper() {
  local py_bin="$1" dst="$2"
  local runtime_lib_path
  runtime_lib_path="$(find /nix/store -type f \( -name 'libstdc++.so.6*' -o -name 'libgomp.so.1*' \) -exec dirname {} + 2>/dev/null | sort -u | paste -sd: -)"
  cat > "${dst}" <<WRAPPER
#!/bin/sh
RUNTIME_LIB_PATH="${runtime_lib_path}"
if [ -n "\${RUNTIME_LIB_PATH}" ]; then
  if [ -n "\${LD_LIBRARY_PATH:-}" ]; then
    export LD_LIBRARY_PATH="\${RUNTIME_LIB_PATH}:\${LD_LIBRARY_PATH}"
  else
    export LD_LIBRARY_PATH="\${RUNTIME_LIB_PATH}"
  fi
fi
exec "${py_bin}" "\$@"
WRAPPER
  chmod 755 "${dst}"
}

# ── Ensure pro envs exist ─────────────────────────────────────────────────────
_hdr "Pro env setup"
for ver_pair in "base:pro:py311" "base-py312:pro-py312:py312" "base-py313:pro-py313:py313"; do
  base_name="${ver_pair%%:*}"
  rest="${ver_pair#*:}"
  pro_name="${rest%%:*}"
  ver="${rest##*:}"
  base_env="/opt/nix/envs/${base_name}"
  pro_env="/opt/nix/envs/${pro_name}"
  wrapper="/usr/local/bin/${ver}"

  if [ ! -d "${base_env}" ]; then
    _fail "Base env missing: ${base_env} — cannot continue"
    continue
  fi

  if [ ! -d "${pro_env}" ]; then
    _fix "Creating pro env: ${pro_env}"
    "${base_env}/bin/python" -m venv --system-site-packages "${pro_env}"
    "${pro_env}/bin/pip" install --upgrade pip --quiet

    # .pth file so pro env sees base + cache site-packages
    pro_site="$("${pro_env}/bin/python" -c "import site; print(site.getsitepackages()[0])")"
    base_site="$("${base_env}/bin/python" -c "import site; print(site.getsitepackages()[0])")"
    echo "${base_site}" > "${pro_site}/_base_env_site.pth"

    _fix "Installing pro packages into ${pro_env}..."

    if [ "${ARCH}" = "x86_64" ]; then
      "${pro_env}/bin/pip" install torch torchvision torchaudio \
        --index-url "${TORCH_INDEX}" --quiet
    else
      "${pro_env}/bin/pip" install torch torchvision torchaudio --quiet
    fi

    "${pro_env}/bin/pip" install \
      tensorflow-cpu \
      transformers datasets tokenizers sentencepiece accelerate \
      mlflow xgboost lightgbm \
      --quiet

    _write_pro_wrapper "${pro_env}/bin/python" "${wrapper}"
    _fix "Updated wrapper: ${wrapper} -> ${pro_env}/bin/python"
  else
    _ok "${pro_env} exists"

    # Ensure wrapper points to pro env
    current_target="$("${wrapper}" -c "import sys; print(sys.executable)" 2>/dev/null || echo '')"
    if echo "${current_target}" | grep -q "envs/pro"; then
      _ok "${ver} wrapper -> pro env"
    else
      _fix "Fixing wrapper ${ver}: was ${current_target}"
      _write_pro_wrapper "${pro_env}/bin/python" "${wrapper}"
    fi
  fi
done

# ── Wrapper sanity ────────────────────────────────────────────────────────────
_hdr "Wrapper check"
for ver in py311 py312 py313; do
  exe="$(/usr/local/bin/${ver} -c "import sys; print(sys.executable)" 2>/dev/null || echo '')"
  if echo "${exe}" | grep -q "envs/pro"; then
    _ok "${ver} -> ${exe}"
  else
    _fail "${ver} -> ${exe} (expected pro env)"
  fi
done

# ── Base DS packages ──────────────────────────────────────────────────────────
_hdr "Base DS packages"
for mod in numpy scipy pandas sklearn matplotlib seaborn pyarrow polars PIL cv2 skimage jupyterlab onnxruntime; do
  for ver in py311 py312 py313; do
    if /usr/local/bin/${ver} -c "import ${mod}" 2>/dev/null; then
      _ok "${ver}: ${mod}"
    else
      _fail "${ver}: ${mod}"
    fi
  done
done

_hdr "PySpark"
for ver in py311 py312 py313; do
  result="$(/usr/local/bin/${ver} -c "import pyspark; print(pyspark.__version__)" 2>/dev/null || echo '')"
  if [ -n "${result}" ]; then
    _ok "${ver}: pyspark ${result}"
  else
    _fail "${ver}: pyspark"
  fi
done

# ── Pro ML packages ───────────────────────────────────────────────────────────
_hdr "PyTorch"
for ver in py311 py312 py313; do
  result="$(/usr/local/bin/${ver} -c "import torch; print(torch.__version__)" 2>/dev/null || echo '')"
  if [ -n "${result}" ]; then
    _ok "${ver}: torch ${result}"
  else
    _fail "${ver}: torch — run with sudo to auto-install"
  fi
done

_hdr "TensorFlow"
for ver in py311 py312 py313; do
  result="$(/usr/local/bin/${ver} -c "import tensorflow; print(tensorflow.__version__)" 2>/dev/null || echo '')"
  if [ -n "${result}" ]; then
    _ok "${ver}: tensorflow ${result}"
  else
    _fail "${ver}: tensorflow"
  fi
done

_hdr "ML ecosystem"
for mod in transformers xgboost lightgbm mlflow; do
  for ver in py311 py312 py313; do
    result="$(/usr/local/bin/${ver} -c "import ${mod}; print(getattr(${mod}, '__version__', 'ok'))" 2>/dev/null || echo '')"
    if [ -n "${result}" ]; then
      _ok "${ver}: ${mod} ${result}"
    else
      _fail "${ver}: ${mod}"
    fi
  done
done

# ── Language runtimes ─────────────────────────────────────────────────────────
_hdr "Language runtimes"
java -version 2>/dev/null   && _ok "java"         || _fail "java"
spark-submit --version 2>&1 | grep -q version && _ok "spark" || _fail "spark"
julia -e "println(VERSION)" 2>/dev/null && _ok "julia" || _fail "julia"
R --version 2>/dev/null     | grep -q "R version" && _ok "R"    || _fail "R"
go version 2>/dev/null      && _ok "go"           || _fail "go"
rustc --version 2>/dev/null && _ok "rustc"        || _fail "rustc"
node --version 2>/dev/null  && _ok "node"         || _fail "node"

# ── Compute smoke test ────────────────────────────────────────────────────────
_hdr "Compute smoke test"

/usr/local/bin/py311 -c "
import torch, numpy as np
x = torch.tensor(np.random.randn(100,100).astype('float32'))
y = torch.mm(x, x.T)
print('  torch matmul OK shape=' + str(tuple(y.shape)) + ' device=' + str(y.device))
" 2>/dev/null && _ok "torch matmul" || _fail "torch matmul"

/usr/local/bin/py311 -c "
import tensorflow as tf
x = tf.random.normal([100,100])
y = tf.matmul(x, tf.transpose(x))
print('  tf matmul OK shape=' + str(tuple(y.shape)))
" 2>/dev/null && _ok "tensorflow matmul" || _fail "tensorflow matmul"

/usr/local/bin/py311 -c "
import xgboost as xgb, numpy as np
X = np.random.randn(100,10).astype('float32')
y = (X[:,0] > 0).astype('float32')
m = xgb.XGBClassifier(n_estimators=5, verbosity=0)
m.fit(X, y)
print('  xgboost fit OK')
" 2>/dev/null && _ok "xgboost fit" || _fail "xgboost fit"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
printf "  Results: %d passed  %d failed  %d fixed/installed\n" "${PASS}" "${FAIL}" "${FIXED}"
echo "════════════════════════════════════════════════════════"
if [ "${FAIL}" -gt 0 ]; then
  echo "  Some checks still failed. Review output above."
  exit 1
else
  echo "  All checks passed."
fi

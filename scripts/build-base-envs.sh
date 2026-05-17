#!/usr/bin/env bash
# build-base-envs.sh — parallel Nix builds for all base Python envs and language
# toolchains.  All packages resolve from cache.nixos.org (binary cache), so each
# build is mostly download-bound.  Firing them all simultaneously cuts the Nix
# provisioning phase from ~25-30 min (sequential) to ~6-10 min (parallel).
set -euo pipefail

FLAKE="/opt/nix/flake"
ENVS="/opt/nix/envs"
LANGS="/opt/nix/langs"

sudo mkdir -p "${ENVS}" "${LANGS}"

# ── Background helper ─────────────────────────────────────────────────────────
# Logs per-build to /tmp/nix-<label>.log so output doesn't interleave.
# Caller captures $! right after each call.

_nix_bg() {
  local label="$1" out="$2" attr="$3"
  local log="/tmp/nix-${label}.log"
  # Redirect inside the sudo command so root writes the log file under /tmp.
  sudo bash -lc \
    "source /etc/profile.d/nix.sh && \
     nix build --max-jobs auto --cores 0 -o ${out} ${FLAKE}#${attr} \
     >\"${log}\" 2>&1" &
}

# ── Launch all builds in parallel ────────────────────────────────────────────
echo "=== Launching parallel Nix builds ==="

_nix_bg "py-base"     "${ENVS}/base"       "py-base"       ; PID_py_base=$!
_nix_bg "py-base-312" "${ENVS}/base-py312" "py-base-py312" ; PID_py312=$!
_nix_bg "py-base-313" "${ENVS}/base-py313" "py-base-py313" ; PID_py313=$!
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
_link "${LANGS}/spark/bin/spark-submit"  /usr/local/bin/spark-submit
_link "${LANGS}/spark/bin/pyspark"       /usr/local/bin/pyspark
_link "${LANGS}/rustc/bin/rustc"         /usr/local/bin/rustc
_link "${LANGS}/cargo/bin/cargo"         /usr/local/bin/cargo
_link "${LANGS}/nodejs/bin/node"         /usr/local/bin/node
_link "${LANGS}/nodejs/bin/npm"          /usr/local/bin/npm

echo ""
echo "Base envs built and linked successfully."

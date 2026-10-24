#!/usr/bin/env bash
set -euo pipefail

# Safe boundary simulation. This does not exploit kernel bugs or attack the
# host. It runs harmless probes under the same systemd restrictions intended
# for the coding agent and expects each forbidden operation to fail.

if [[ "$(uname -s)" != "Linux" ]] || ! command -v systemd-run >/dev/null 2>&1; then
  echo "SKIP: adversarial runtime simulation requires a Linux systemd guest"
  exit 0
fi

if ! id agent >/dev/null 2>&1; then
  echo "FAIL: agent user is missing" >&2
  exit 1
fi

report_dir="${AGENT_SANDBOX_REPORT_DIR:-/var/log/agent-sandbox}"
mkdir -p "$report_dir"
report="$report_dir/adversarial-$(date -u +%Y%m%dT%H%M%SZ).tsv"
printf 'timestamp\tprobe\tcontrol\texpected\tstatus\tresult\tdetail\n' >"$report"
echo "evidence report: $report"

common=(
  --quiet --wait --pipe --collect
  --uid=agent --gid=agent
  --working-directory=/workspace
  --property=NoNewPrivileges=yes
  --property=CapabilityBoundingSet=
  --property=AmbientCapabilities=
  --property=PrivateDevices=yes
  --property=PrivateTmp=yes
  --property=ProtectSystem=strict
  --property=ProtectHome=yes
  --property=ProtectKernelTunables=yes
  --property=ProtectKernelModules=yes
  --property=ProtectKernelLogs=yes
  --property=ProtectControlGroups=yes
  --property=RestrictSUIDSGID=yes
  --property=LockPersonality=yes
  --property=MemoryDenyWriteExecute=yes
  --property=RestrictNamespaces=yes
  --property=RestrictRealtime=yes
  --property=RestrictAddressFamilies=AF_UNIX
  --property=IPAddressDeny=any
  --property=SystemCallArchitectures=native
  --property=SystemCallFilter=~@clock @debug @keyring @module @mount @obsolete @raw-io @reboot @swap @cpu-emulation io_uring_setup io_uring_enter io_uring_register userfaultfd bpf perf_event_open ptrace process_vm_readv process_vm_writev pidfd_getfd keyctl add_key request_key kexec_load kexec_file_load init_module finit_module delete_module
  --property=ReadWritePaths=/workspace /tmp
  --property=PrivateMounts=yes
)

run_probe() {
  local name="$1" control="$2" expected="$3" command="$4" output status result detail
  set +e
  output="$(systemd-run "${common[@]}" /bin/bash -c "$command" 2>&1)"
  status=$?
  set -e
  detail="$(printf '%s' "$output" | tr '\t\r\n' '   ' | cut -c1-500)"

  if [[ "$expected" == "deny" && "$status" -ne 0 ]]; then
    result=PASS
    echo "PASS: $name denied"
  elif [[ "$expected" == "deny" && "$status" -eq 0 ]]; then
    result=FAIL
    echo "FAIL: $name was allowed" >&2
    printf '%s\n' "$output" >&2
  elif [[ "$expected" == "allow" && "$status" -eq 0 ]]; then
    result=PASS
    echo "PASS: $name allowed"
  elif [[ "$expected" == "allow" && "$status" -ne 0 ]]; then
    result=FAIL
    echo "FAIL: $name was unexpectedly denied" >&2
    printf '%s\n' "$output" >&2
  else
    result=INFO
    echo "INFO: $name status=$status"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$control" "$expected" "$status" "$result" "$detail" >>"$report"
  [[ "$result" != FAIL ]]
}

failures=0
run_probe "workspace write" "ReadWritePaths" allow "touch /workspace/.sandbox-probe && rm -f /workspace/.sandbox-probe" || failures=$((failures + 1))
run_probe "temporary write" "ReadWritePaths" allow "touch /tmp/.sandbox-probe && rm -f /tmp/.sandbox-probe" || failures=$((failures + 1))
run_probe "write protected system" "ProtectSystem" deny "touch /etc/agent-sandbox-probe" || failures=$((failures + 1))
run_probe "read protected home" "ProtectHome" deny "cat /home/ubuntu/.ssh/authorized_keys" || failures=$((failures + 1))
run_probe "read host init root" "ProtectSystem/namespace" deny "cat /proc/1/root/etc/shadow" || failures=$((failures + 1))
run_probe "write kernel sysctl" "ProtectKernelTunables" deny "echo 0 > /proc/sys/kernel/yama/ptrace_scope" || failures=$((failures + 1))
run_probe "write sysfs" "ProtectKernelTunables" deny "echo 1 > /sys/kernel/debug/tracing/tracing_on" || failures=$((failures + 1))
run_probe "create mount namespace" "RestrictNamespaces" deny "unshare -m true" || failures=$((failures + 1))
run_probe "mount filesystem" "SystemCallFilter/@mount" deny "mkdir -p /tmp/probe-mount; mount -t tmpfs none /tmp/probe-mount" || failures=$((failures + 1))
run_probe "access kvm device" "PrivateDevices" deny "test -r /dev/kvm" || failures=$((failures + 1))
run_probe "open raw network family" "RestrictAddressFamilies" deny "python3 -c 'import socket; socket.socket(socket.AF_PACKET, socket.SOCK_RAW, 0)'" || failures=$((failures + 1))
run_probe "reach external IP" "IPAddressDeny" deny "python3 -c 'import socket; socket.create_connection((\"1.1.1.1\", 443), 1)'" || failures=$((failures + 1))
run_probe "use ptrace" "SystemCallFilter/ptrace" deny "python3 -c 'import ctypes; ctypes.CDLL(None).ptrace(0, 0, 0, 0)'" || failures=$((failures + 1))
run_probe "load bpf" "SystemCallFilter/bpf" deny "python3 -c 'import ctypes, platform; n={\"x86_64\":321, \"aarch64\":280, \"arm64\":280}[platform.machine()]; ctypes.CDLL(None, use_errno=True).syscall(n, 0, 0, 0, 0, 0)'" || failures=$((failures + 1))
run_probe "inspect capabilities" "CapabilityBoundingSet/AmbientCapabilities" deny "grep -E 'Cap(Inh|Prm|Eff|Bnd|Amb):[[:space:]]+[1-9a-f]' /proc/self/status" || failures=$((failures + 1))
run_probe "use io_uring" "SystemCallFilter/io_uring" deny "python3 -c 'import ctypes; ctypes.CDLL(None).syscall(425, 0, 0, 0)'" || failures=$((failures + 1))
run_probe "use userfaultfd" "SystemCallFilter/userfaultfd" deny "python3 -c 'import ctypes, platform; n={\"x86_64\":323, \"aarch64\":282, \"arm64\":282}[platform.machine()]; ctypes.CDLL(None).syscall(n, 0)'" || failures=$((failures + 1))

if (( failures > 0 )); then
  echo "adversarial simulation failed: $failures probe(s) escaped policy" >&2
  exit 1
fi

echo "adversarial simulation passed"

#!/usr/bin/env bash
set -euo pipefail

failures=0

check_eq() {
  local key="$1" expected="$2" actual
  actual="$(sysctl -n "$key" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $key expected=$expected actual=${actual:-missing}" >&2
    failures=$((failures + 1))
  else
    echo "PASS: $key=$actual"
  fi
}

check_absent() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "FAIL: unexpected path/device present: $path" >&2
    failures=$((failures + 1))
  else
    echo "PASS: absent $path"
  fi
}

check_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing $path" >&2
    failures=$((failures + 1))
  else
    echo "PASS: present $path"
  fi
}

check_eq kernel.unprivileged_bpf_disabled 1
check_eq vm.unprivileged_userfaultfd 0
check_eq kernel.perf_event_paranoid 3
check_eq kernel.kexec_load_disabled 1
check_eq kernel.yama.ptrace_scope 2

if [[ -e /proc/sys/kernel/io_uring_disabled ]]; then
  check_eq kernel.io_uring_disabled 2
else
  echo "WARN: kernel.io_uring_disabled is unavailable; service syscall filter must remain enabled"
fi

check_file /etc/modprobe.d/agent-sandbox.conf
check_file /usr/local/libexec/agent-sandbox-exec
check_file /etc/systemd/system/agent-sandbox@.service
check_file /etc/systemd/system/agent-sandbox-proc.service

for device in /dev/kvm /dev/mem /dev/kmem /dev/port /dev/fuse /dev/vfio /dev/dri; do
  check_absent "$device"
done

if id agent >/dev/null 2>&1; then
  echo "PASS: agent user exists"
else
  echo "FAIL: agent user missing" >&2
  failures=$((failures + 1))
fi

if grep -q 'NoNewPrivileges=yes' /etc/systemd/system/agent-sandbox@.service; then
  echo "PASS: systemd no-new-privileges policy present"
else
  echo "FAIL: systemd no-new-privileges policy missing" >&2
  failures=$((failures + 1))
fi

if grep -q '^CapabilityBoundingSet=$' /etc/systemd/system/agent-sandbox@.service &&
   grep -q '^AmbientCapabilities=$' /etc/systemd/system/agent-sandbox@.service; then
  echo "PASS: capability bounding and ambient capability policies present"
else
  echo "FAIL: capability bounding policy missing" >&2
  failures=$((failures + 1))
fi

if grep -q '^IPAddressDeny=any$' /etc/systemd/system/agent-sandbox@.service; then
  echo "PASS: IP address egress deny policy present"
else
  echo "FAIL: IP address egress deny policy missing" >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  echo "agent sandbox verification failed: $failures check(s)" >&2
  exit 1
fi

echo "agent sandbox verification passed"

#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "must run as root" >&2
  exit 1
fi

install -d -m 0755 /etc/sysctl.d /etc/modprobe.d /etc/systemd/system /usr/local/libexec

cat >/etc/sysctl.d/90-agent-sandbox.conf <<'EOF'
# Interfaces that are not required by an agent and expand the kernel attack
# surface. The launcher also blocks these through systemd syscall filtering.
kernel.unprivileged_bpf_disabled = 1
vm.unprivileged_userfaultfd = 0
kernel.perf_event_paranoid = 3
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 2
fs.protected_fifos = 2
fs.protected_regular = 2
EOF

# Newer Ubuntu kernels expose this host-wide switch. Older kernels are still
# protected by the per-service syscall filter below.
if [[ -e /proc/sys/kernel/io_uring_disabled ]]; then
  echo 'kernel.io_uring_disabled = 2' >>/etc/sysctl.d/90-agent-sandbox.conf
fi

cat >/etc/modprobe.d/agent-sandbox.conf <<'EOF'
install algif_aead /bin/true
install fuse /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install hfs /bin/true
install hfsplus /bin/true
install jffs2 /bin/true
install udf /bin/true
install dccp /bin/true
install rds /bin/true
install sctp /bin/true
install tipc /bin/true
EOF

for mod in algif_aead fuse cramfs freevxfs hfs hfsplus jffs2 udf dccp rds sctp tipc; do
  rmmod "$mod" 2>/dev/null || true
done

sysctl --system >/dev/null

if ! id agent >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/agent --shell /usr/sbin/nologin agent
fi
usermod --lock agent
install -d -o agent -g agent -m 0700 /home/agent /workspace

cat >/etc/systemd/system/agent-sandbox-proc.service <<'EOF'
[Unit]
Description=Restrict guest procfs process visibility
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/mount -o remount,hidepid=2 /proc
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable agent-sandbox-proc.service

chmod 0755 /usr/local/libexec/agent-sandbox-exec
install -d -m 0755 /opt/agent /workspace

echo "agent sandbox hardening applied"

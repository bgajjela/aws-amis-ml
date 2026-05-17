# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: bgajjela@gmail.com  
Subject line: `[SECURITY] CPU DS/ML AMI — <brief description>`

Include:
- CVE ID if one exists
- Affected AMI versions / build timestamps
- Description of the vulnerability and impact
- Steps to reproduce (if applicable)

We aim to acknowledge reports within **2 business days** and provide a
remediation timeline within **7 business days**.

---

## Supported Versions

| AMI | Status |
|---|---|
| Latest published version | Actively maintained |
| Previous version (n-1) | Security patches only |
| Older versions | End of life — upgrade recommended |

AMI builds are timestamped in the name: `cpu-ds-ml-ubuntu-2204-{base|pro}-<timestamp>`.
Check `/usr/share/BUILD_INFO` on a running instance for the exact build date.

---

## Security Advisories

### CVE-2026-31431 — Copy Fail (local privilege escalation)

| Field | Detail |
|---|---|
| **CVE** | CVE-2026-31431 |
| **Severity** | High |
| **Component** | `algif_aead` Linux kernel module (AF_ALG AEAD socket) |
| **Affected kernels** | 4.14 – 6.19.12 |
| **Ubuntu 22.04 kernel** | 5.15.x — within affected range |
| **Impact** | Local privilege escalation to root for any active user session |
| **Remediated in AMI build** | Commit `564c10b` (2026-05-17) |
| **Reference** | https://cisecurity.atlassian.net/wiki/spaces/CSKB/pages/5164630160/ |

**What was done in the AMI build (commit `564c10b`):**

1. `algif_aead` blacklisted in `/etc/modprobe.d/cis-blacklist.conf` — module
   cannot load on any instance launched from this AMI. Takes effect immediately
   at boot; no workload on this AMI requires the AF_ALG kernel socket
   (PyTorch, TensorFlow, OpenSSL all use userspace crypto).

2. Packer base build now reboots into the patched kernel before snapshotting
   the AMI — ensures the kernel patch is *running*, not just installed.

**If you are running instances launched from an older AMI build:**

The kernel patch is delivered automatically by `unattended-upgrades` (enabled
on all AMI builds). To complete remediation on running instances:

```bash
# 1. Verify the patch is installed (look for linux-image version >= patched version)
apt list --installed 2>/dev/null | grep linux-image

# 2. Reboot to activate the patched kernel
sudo reboot

# 3. After reboot — verify algif_aead cannot load (should print "install /bin/true")
grep algif_aead /etc/modprobe.d/cis-blacklist.conf || echo "NOT PRESENT — upgrade AMI"

# 4. Confirm module is not loaded
lsmod | grep algif_aead || echo "algif_aead not loaded — expected"
```

If `/etc/modprobe.d/cis-blacklist.conf` does not contain `algif_aead`, your
instance was launched from a pre-remediation AMI. Apply the interim mitigation
manually:

```bash
sudo tee -a /etc/modprobe.d/cis-blacklist.conf <<'EOF'
# CVE-2026-31431 interim mitigation
install algif_aead /bin/true
EOF
sudo rmmod algif_aead 2>/dev/null || true
sudo update-initramfs -u
```

Then reboot to activate the patched kernel.

---

## General Security Posture

Every AMI build applies the following before publishing:

- **CIS Ubuntu 22.04 LTS Benchmark L1+L2**: 114 controls, 0 failures
- **`apt-get upgrade`** at build time: all Ubuntu security patches applied
- **Kernel reboot** at build time: patched kernel confirmed running in snapshot
- **`unattended-upgrades`** enabled: running instances receive security patches automatically
- **On-demand CVE scan**: `sudo ami-scan` (Trivy + OpenSCAP) — run anytime
- **EBS encryption** at rest; **IMDSv2** enforced; **SSH** key-only, no root login

For the full control list see `SECURITY_REPORT.md`.

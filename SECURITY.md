# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: dimenpoint@gmail.com  
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
| **Remediated in AMI build** | Applied 2026-05-17 |
| **Reference** | https://cisecurity.atlassian.net/wiki/spaces/CSKB/pages/5164630160/ |

**What was done in the AMI build (applied 2026-05-17):**

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

---

## Verifying release signatures

All releases are GPG-signed. To verify:

```bash
# 1. Import the maintainer's public key
gpg --keyserver keyserver.ubuntu.com --recv-keys 32BCD1C307771BAD

# 2. Verify the signed tag
git fetch --tags
git tag -v 1.0.0
```

Expected output includes: `Good signature from "Bharath Kumar Gajjela <bgajjela@gmail.com>"`

The public key fingerprint is: `C06D 6AF1 DA1E E331 3768 2DF0 32BC D1C3 0777 1BAD`

---

## Assurance case

### Threat model

| Threat | Mitigations |
|--------|-------------|
| Local privilege escalation | ASLR enabled, core dumps restricted, kernel module blacklist (algif_aead), sudo timestamp_timeout, CIS L2 controls |
| Lateral movement via SSH | SSHv2 only, key-based auth, root login disabled, HostKeyAlgorithms restricted, SSM-only recommended |
| Supply chain compromise | AWS CLI verified via PGP, Trivy installed via pinned commit SHA, all CI actions pinned by commit SHA, CycloneDX SBOM |
| SSRF / metadata abuse | IMDSv2 enforced — token-required, no v1 fallback |
| Credential exposure | ami-finalize.sh wipes SSH host keys, bash history, and cloud-init state before snapshot |
| Vulnerable packages | Trivy CVE scan in CI (HIGH/CRITICAL exit-code 1), unattended-upgrades on running instances |
| Misconfigured infrastructure | Checkov Packer IaC scan in CI |

### Trust boundaries

- **Outside trust boundary**: the AWS hypervisor, EC2 network, upstream Ubuntu package mirrors, external Nix package cache
- **Inside trust boundary**: AMI build process, provisioner scripts, Nix environments, hardening controls

### Secure design principles applied

- **Least privilege**: no root SSH, sudo timestamp_timeout, restricted kernel modules, IMDSv2 token-required
- **Defense in depth**: CIS L1+L2 + STIG-aligned additions + Trivy + unattended-upgrades — multiple independent layers
- **Fail secure**: Trivy HIGH/CRITICAL findings fail CI hard; Packer build fails on provisioner errors
- **Minimal attack surface**: SSM-only access (no open port 22), unnecessary kernel modules blacklisted, unused services disabled

### Common implementation weaknesses countered

- **Injection**: ShellCheck enforces proper quoting and variable expansion in all scripts
- **Insecure defaults**: All hardening applied at build time — instances launch hardened, not hardened later
- **Broken cryptography**: SHA-1, MD5, RC4, CBC mode SSH disabled; TLS 1.2 minimum enforced
- **Exposed credentials**: Trivy secret scanning on every CI push; ami-finalize.sh wipes credentials before snapshot

---

## Disclaimer

THIS AMI IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

**Your responsibility.** You are solely responsible for evaluating whether this
AMI meets your organization's security requirements, validating controls against
your own compliance obligations, and maintaining the security posture of any
instance you launch. Hardening controls applied at build time do not substitute
for ongoing operational security practices.

**Limitation of liability.** To the maximum extent permitted by applicable law,
Dimenpoint shall not be liable for any direct, indirect, incidental, special,
consequential, or punitive damages arising from your use of, or inability to use,
this AMI — including but not limited to data loss, unauthorized access, security
incidents, compliance failures, or service interruptions — even if advised of
the possibility of such damages.

**No compliance guarantee.** The presence of CIS benchmark controls does not constitute a guarantee of
compliance with any regulatory framework, including SOC 2, HIPAA, PCI-DSS,
FedRAMP, or ISO 27001. Engage a qualified auditor for formal compliance
assessments applicable to your use case.

**AWS terms govern.** Your use of this AMI through AWS Marketplace is subject
to the AWS Customer Agreement and the AWS Standard Contract for AWS Marketplace.
In the event of any conflict between this document and those agreements, the
AWS terms control.

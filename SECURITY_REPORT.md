Security Hardening Summary (CIS-aligned)

Overview
- This document summarizes the hardening controls applied by `harden.sh` and how to verify them on an instance built from this AMI.
- Many settings require a reboot to fully take effect (e.g., tmpfs mounts, GRUB audit flag). Most others are immediate.

SSH Hardening
- Password and keyboard-interactive disabled; pubkey only. Root login disabled. Safer crypto, reduced attack surface.
- Config path: /etc/ssh/sshd_config
- Verify:
  - `sshd -T | egrep 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin|challengeresponseauthentication|x11forwarding|usedns|printlastlog|banner'`
  - Expect: passwordauthentication no, kbdinteractiveauthentication no, permitrootlogin no, usedns no, x11forwarding no, printlastlog yes, banner /etc/issue.net

Login Banner
- Files: /etc/issue, /etc/issue.net (legal notice); Banner enabled in sshd.
- Verify: `stat -c '%a %U:%G %n' /etc/issue /etc/issue.net` (expect 644 root:root)

Firewall (UFW)
- Default deny inbound, allow outbound; OpenSSH allowed and rate-limited; logging enabled.
- Verify:
  - `ufw status verbose`
  - Expect: Status active; Default: deny (incoming), allow (outgoing); OpenSSH ALLOW and LIMIT rules.

System Updates and Services
- unattended-upgrades installed and configured; chrony and auditd enabled.
- Verify: `systemctl is-enabled chrony auditd` (expect enabled)

Ulimits
- Login sessions: nofile 65535, nproc 16384, core 0, memlock 65536 via /etc/security/limits.d/99-ulimits.conf
- Systemd defaults: DefaultLimitNOFILE=65535, DefaultLimitNPROC=16384, DefaultLimitCORE=0, DefaultLimitMEMLOCK=65536
- Verify:
  - `ulimit -n` in a new login shell; check `systemctl show --property DefaultLimitNOFILE`.

Filesystem and Directory Hardening
- /tmp and /var/tmp configured as tmpfs (mode 1777, nodev,nosuid,noexec) via tmp.mount and var-tmp.mount.
- /dev/shm hardened via fstab (nodev,nosuid,noexec,mode=1777).
- World-writable dirs have sticky bit; homes set to 0750 (root 0700), tightened umask to 027.
- Verify:
  - `systemctl status tmp.mount var-tmp.mount` (after reboot should be active)
  - `mount | egrep '/tmp|/var/tmp|/dev/shm'` and confirm mount options
  - `namei -m /home/ubuntu` and `stat -c '%a' /home/* /root`
  - `umask` in a new login shell (expect 0027)

Sysctl Network and Kernel Hardening
- Applied via /etc/sysctl.d/99-cis-net.conf and 99-cis-fs.conf.
- Highlights: redirect/source-route off, rp_filter on, syncookies on, IPv6 RA/redirects off, ASLR on, protected_{symlinks,hardlinks,fifos,regular}=1/2, kptr/dmesgrestrict, perf_event_paranoid, yama.
- Verify: `sysctl -a | egrep 'accept_redirects|accept_source_route|send_redirects|rp_filter|tcp_syncookies|randomize_va_space|suid_dumpable|protected_(hardlinks|symlinks|fifos|regular)|kptr_restrict|dmesg_restrict|perf_event_paranoid|ptrace_scope'`

Auditd
- Watch rules installed: identity files, sudoers, sshd_config, sysctl, audit config, time changes, modules; immutable rules.
- GRUB audit=1 set for boot-time auditing.
- Verify:
  - `auditctl -s` (enabled), `auditctl -l | head` shows rules, `grep audit=1 /proc/cmdline` after reboot

AppArmor, AIDE, PAM
- AppArmor installed and enforcing; AIDE DB initialized.
- Password quality enforced (minlen=14, character classes), password history remember=5; faillock policy deny=5 unlock_time=900; su restricted to sudo.
- Verify:
  - `aa-status` (profiles in enforce mode)
  - `grep -E 'minlen|dcredit|ucredit|lcredit|ocredit|remember' /etc/security/pwquality.conf`
  - `grep faillock /etc/pam.d/common-*` and `grep pam_wheel /etc/pam.d/su`
  - `test -f /var/lib/aide/aide.db && echo AIDE DB present`

Log Management
- logrotate: weekly, rotate 14, compress+delaycompress, dateext; UFW log rotation added.
- journald: persistent, compressed, size caps (500M system, 200M runtime), Seal=yes.
- Verify:
  - `grep -E 'weekly|rotate|compress|dateext' /etc/logrotate.conf`
  - `journalctl --disk-usage` and `grep -R '\[Journal\]' /etc/systemd/journald.conf.d`

Cron/At Restrictions
- Only root allowed; deny files removed.
- Verify: `ls -l /etc/cron.allow /etc/at.allow` and `test ! -f /etc/cron.deny && echo ok`

Banner and Legal Notices
- Local login banner at /etc/issue; SSH banner at /etc/issue.net; enabled via sshd_config Banner.
- Verify: `sshd -T | grep banner` and `cat /etc/issue{,.net}`

Notes
- Some settings (tmp mounts, GRUB audit) require reboot.
- If services need execution in temp, use dedicated work dirs; do not relax noexec on /tmp globally.


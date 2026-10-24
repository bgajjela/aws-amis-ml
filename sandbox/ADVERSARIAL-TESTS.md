# Adversarial sandbox test matrix

`adversarial-agent-sim.sh` runs harmless boundary probes as the unprivileged
`agent` user through the same systemd policy used by the coding agent. A probe
passes when the intended operation is denied, or when a narrowly scoped
workspace/temporary write is allowed.

| Attempt | Intended resolution |
| --- | --- |
| Write `/etc` | `ProtectSystem=strict`, non-root user |
| Read another user's home or SSH material | `ProtectHome=yes` |
| Traverse PID 1's root to reach host-like files | proc isolation plus guest-only VM boundary |
| Change kernel sysctls or write debug sysfs | `ProtectKernelTunables=yes`, `ProtectKernelLogs=yes` |
| Create a mount namespace or mount a filesystem | `RestrictNamespaces=yes`, mount syscall deny list |
| Open KVM and other host devices | `PrivateDevices=yes`, image device checks |
| Create raw or packet sockets | `RestrictAddressFamilies=AF_UNIX` |
| Reach an external IP | `IPAddressDeny=any` |
| Use `ptrace`, BPF, io_uring, or userfaultfd | systemd syscall filter plus kernel sysctls |
| Load kernel modules, kexec, keyrings, or raw I/O | systemd syscall filter, module blacklist, kernel policy |
| Retain or gain capabilities | empty `CapabilityBoundingSet` and `AmbientCapabilities`, launcher `no_new_privs` |
| Write task files | only `/workspace` and `/tmp` are writable |

Each run writes a timestamped TSV file under `/var/log/agent-sandbox/` with:

- timestamp and probe name;
- control being tested;
- expected outcome;
- `systemd-run` status;
- pass/fail result;
- truncated command output for diagnosis.

This is a boundary regression suite, not a proof that the kernel or hypervisor
has no vulnerabilities. It deliberately does not execute kernel exploits,
credential theft, persistence, or destructive payloads. Full assurance still
requires running the resulting AMI in a disposable account/region and testing
the outer Firecracker/Kata/EC2, IAM, metadata, network, and credential-broker
controls separately.

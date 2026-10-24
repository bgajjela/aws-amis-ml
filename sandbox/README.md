# Agent Sandbox AMI

This is a separate Packer pipeline for building an agent-sandbox AMI from an
existing CPU DS/ML Ubuntu 22.04 AMI. It does not modify or participate in the
existing base/pro AMI pipeline.

The sandbox image is intended to be used as a guest image inside Firecracker,
Kata Containers, or another VM boundary. It is not a replacement for the VM,
host, AWS IAM, security-group, egress-proxy, or credential-broker controls.

## Build

Build the normal base AMI first, then pass its ID explicitly:

```bash
cd sandbox
packer init .
packer validate -var 'base_ami_id=ami-xxxxxxxxxxxxxxxxx' -var 'region=us-east-1' .
packer build -var 'base_ami_id=ami-xxxxxxxxxxxxxxxxx' -var 'region=us-east-1' .
```

The build never installs coding agents or downloads runtime plugins. Agents
must be baked into a reviewed image release separately, or included in the
source AMI before this layer is built.

## Runtime contract

The image assumes that the launcher or VM layer will provide:

- one disposable VM per task;
- no host filesystem mounts;
- no credentials in the guest;
- no cloud metadata access;
- no devices except those required for boot;
- no network, or an external allowlisted egress proxy;
- destruction after task completion or timeout.

Use `/usr/local/libexec/agent-sandbox-exec` as the entrypoint for an already
installed agent. It applies `no_new_privs` and clears capabilities. The
provided systemd unit adds the filesystem and syscall policy.

## Verification

```bash
sudo bash verify-agent-sandbox.sh
bash adversarial-agent-sim.sh
```

The adversarial run writes a timestamped TSV evidence report under
`/var/log/agent-sandbox/`. It records each attempted operation, expected
control, exit status, and captured denial detail. The verifier checks image-local controls. It cannot prove the EC2 host,
hypervisor, VMM, network, or IAM configuration.

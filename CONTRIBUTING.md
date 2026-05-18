# Contributing

Thanks for your interest in contributing. This project builds a CIS-hardened Ubuntu 22.04 AMI for ML/DS workloads on AWS.

## Ways to contribute

- **Bug reports** — open an issue with reproduction steps and the output of `sudo ami-scan`
- **CIS control gaps** — if you find a benchmark that isn't applied, open an issue referencing the control ID (e.g. `CIS 5.2.1`)
- **New toolchain support** — additional language runtimes or ML frameworks via Nix
- **ARM64 parity** — issues specific to Graviton3 builds
- **Documentation** — corrections to README, USAGE.md, or inline script comments

## Getting started

```bash
git clone https://github.com/bgajjela/aws-amis-ml.git
cd aws-amis-ml
cp vars.example.pkrvars.hcl my.pkrvars.hcl   # fill in subnet_id, security_group_id
```

**Prerequisites:** Packer ≥ 1.9, AWS credentials with EC2 + SSM permissions, ShellCheck.

## Making changes

1. Fork the repo and create a branch: `fix/cis-5-2-1` or `feat/add-rust-nightly`
2. Run ShellCheck before pushing:
   ```bash
   shellcheck -S warning harden.sh scripts/*.sh
   ```
3. Run the CIS compliance check:
   ```bash
   bash tests/cis-check.sh
   ```
4. Open a pull request against `main` — describe the control ID or use case your change addresses

## Hardening script conventions

- All `harden.sh` changes must reference the CIS benchmark control ID in a comment
- `sysctl` changes go in the sysctl block, not ad hoc inline
- Kernel module blacklists go in `/etc/modprobe.d/cis-blacklist.conf`

## Reporting security vulnerabilities

Do not open a public issue. See [SECURITY.md](SECURITY.md) for the private disclosure process.

## License

By contributing you agree your changes are licensed under [Apache 2.0](LICENSE).

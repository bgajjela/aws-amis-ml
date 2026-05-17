# AMI Provisioning Simulation (Docker)

This container build reproduces the shell provisioner steps from `packer.pkr.hcl`
so you can exercise the AMI recipe locally without touching AWS. The image runs
the exact `nix build` invocations for the base or pro variants (including
`mlflow` in the pro env) and executes the same smoke tests used in the Packer
templates.

## Prerequisites

- Docker (BuildKit/Buildx enabled)
- Network access to fetch packages from Ubuntu and Nix

## Build

From the repository root:

```bash
# Build the base variant (minimal DS/ML tooling)
docker build \
  -t ami-sim-base \
  -f docker-sim/Dockerfile \
  docker-sim

# Build the pro variant (includes mlflow, torch, etc.)
docker build \
  --build-arg AMI_VARIANT=pro \
  -t ami-sim-pro \
  -f docker-sim/Dockerfile \
  docker-sim
```

## Run & Inspect

```bash
# Drop into a shell inside the container
docker run -it --rm ami-sim-pro

# Validate toolchains inside the container shell
py311 -c "import mlflow; print(mlflow.__version__)"
spark-submit --version
julia -e 'println(VERSION)'
R --version
```

All provisioning artifacts land under `/opt/nix` and `/usr/share/examples/spark`
exactly as they do in the AMI builds.

## Notes & Differences

- `systemctl` calls are stubbed to succeed because the container does not run
  systemd; other commands run unmodified.
- `harden.sh` executes, but service enable/start operations become no-ops in the
  container (they still validate syntax and write config files).
- The Docker build copies `nix/flake.nix`, Spark helper scripts, and example
  jobs so they remain in sync with the Packer inputs.

Use this workflow before running `packer build` to confirm the provisioning
logic and Python environments succeed end-to-end without allocating EC2
instances.

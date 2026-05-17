This product includes Ubuntu 22.04 LTS and various open-source components distributed under their respective licenses. You are purchasing packaging/configuration/support only.

Key components and sources
- Nixpkgs (nixos-24.05, nixpkgs-unstable) for language runtimes and tools
- Python packages (via mach-nix/pip) including scientific/ML/AI libraries (numpy, pandas, scikit-learn, torch, tensorflow, etc.)
- Julia, R, Go toolchains; OpenJDK 17; Apache Spark

License information
- Licenses for system packages are provided by Ubuntu and Nixpkgs maintainers.
- Python package licenses are provided by upstream projects. See project repositories and PyPI pages.
- On running instances, you may enumerate dependencies with:
  - `nix-store --query --requisites /opt/nix/envs/base` and inspect derivations
  - `nix run /opt/nix/flake#env-report-base` (pip list), similarly for pro

No ownership of third-party IP is claimed. All trademarks are the property of their respective owners.


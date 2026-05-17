packer {
  required_plugins {
    amazon = { source = "github.com/hashicorp/amazon", version = ">= 1.3.0" }
  }
}

variable "region" { default = "us-east-1" }
locals { base_name = "cpu-ds-ml-ubuntu-2204" }

# Discovers the most-recently-built base AMI so the pro build can layer on top
# instead of repeating all hardening/toolchain work (~1.5h saved per build).
# Run base first: packer build -only=cpu-ds-ml-base .
# Then run pro:   packer build -only=cpu-ds-ml-pro .
data "amazon-ami" "base" {
  region      = var.region
  most_recent = true
  owners      = ["self"]
  filters = {
    name                = "${local.base_name}-base-*"
    "tag:Role"          = "dsml"
    virtualization-type = "hvm"
  }
}

# -------- Sources (one per AMI so we can set names/descriptions) --------
source "amazon-ebs" "ubuntu_base" {
  region                      = var.region
  ssh_username                = "ubuntu"
  ena_support                 = true
  instance_type               = var.instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Enforce IMDSv2: prevents SSRF attacks from stealing EC2 role credentials via IMDSv1
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  # Wire EBS encryption variables declared at the bottom of this file
  encrypt_boot = var.encrypt_ebs
  kms_key_id   = var.kms_key_id

  source_ami_filter {
    owners      = ["099720109477"] # Canonical
    most_recent = true
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = var.encrypt_ebs
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
  }

  ami_name        = "${local.base_name}-base-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Base) - Ubuntu 22.04, pinned minimal stack, CIS-style hardened"
  tags = { Name = "${local.base_name}-base", Role = "dsml" }
}

source "amazon-ebs" "ubuntu_pro" {
  region                      = var.region
  ssh_username                = "ubuntu"
  ena_support                 = true
  instance_type               = var.instance_type
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = var.associate_public_ip
  ami_regions                 = var.additional_regions

  # Start from the already-hardened base AMI — avoids repeating ~1.5h of work
  # (apt upgrade, hardening, Nix setup, Julia/R/Go/Java/Spark, base Python envs).
  source_ami = data.amazon-ami.base.id

  # Enforce IMDSv2: prevents SSRF attacks from stealing EC2 role credentials via IMDSv1
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  encrypt_boot = var.encrypt_ebs
  kms_key_id   = var.kms_key_id

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = var.encrypt_ebs
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
  }

  ami_name        = "${local.base_name}-pro-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Pro) - Ubuntu 22.04, full DL stack (torch/tf/transformers), CIS-hardened"
  tags = { Name = "${local.base_name}-pro", Role = "dsml" }
}

# =======================
# BASE IMAGE (minimal)
# =======================
build {
  name    = "cpu-ds-ml-base"
  sources = ["source.amazon-ebs.ubuntu_base"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      # Apply all Ubuntu security patches (OpenSSL, curl, glibc, systemd, etc.) before installing anything
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      # unzip + gnupg needed for AWS CLI v2 download and PGP verification; awscli (v1, EOL) replaced by v2 below
      "sudo apt-get -y install curl jq git-lfs unzip gnupg build-essential python3-venv ca-certificates xz-utils",
      "sudo apt-get -y install ufw auditd fail2ban unattended-upgrades logrotate chrony",
      "sudo systemctl enable auditd chrony unattended-upgrades",
      "sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sshd -t && sudo systemctl reload ssh || true",
      "sudo mkdir -p /opt/venvs /usr/share",
      "sudo chown -R ubuntu:ubuntu /opt/venvs",
      "python3 -m venv /opt/venvs/py311",
      "sudo chmod 755 /opt/venvs/py311",
      # Install AWS CLI v2 with PGP signature verification (key: FB5DB77FD5C118B80511ADA8A6310ACC4672475C)
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o /tmp/awscliv2.zip",
      "curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig' -o /tmp/awscliv2.sig",
      "gpg --keyserver hkps://keys.openpgp.org --recv-keys FB5DB77FD5C118B80511ADA8A6310ACC4672475C",
      "gpg --verify /tmp/awscliv2.sig /tmp/awscliv2.zip",
      "unzip -q /tmp/awscliv2.zip -d /tmp",
      "sudo /tmp/aws/install",
      "rm -rf /tmp/awscliv2.zip /tmp/awscliv2.sig /tmp/aws",
      # Pin Nix installer to a specific version to prevent supply-chain risk from unversioned curl|sh
      # Update this pin periodically: https://releases.nixos.org/nix/
      "curl -fsSL -o /tmp/install-nix.sh https://releases.nixos.org/nix/nix-2.24.9/install",
      "yes | sudo -E sh /tmp/install-nix.sh --daemon || true",
      "echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' | sudo tee /etc/profile.d/nix.sh",
      "echo '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' | sudo tee -a /home/ubuntu/.profile",
      "sudo chown ubuntu:ubuntu /home/ubuntu/.profile || true",
      "sudo systemctl enable nix-daemon || true",
      "sudo systemctl start nix-daemon || true",
    ]
  }

  # Nix flake for reproducible Python envs (base/pro defined inside flake)
  provisioner "file" {
    source      = "nix/flake.nix"
    destination = "/tmp/flake.nix"
  }
  provisioner "file" {
    source      = "scripts/spark-java.sh"
    destination = "/tmp/spark-java.sh"
  }
  provisioner "file" {
    source      = "scripts/build-base-envs.sh"
    destination = "/tmp/build-base-envs.sh"
  }
  provisioner "file" {
    source      = "examples/pyspark_basic.py"
    destination = "/tmp/pyspark_basic.py"
  }
  provisioner "file" {
    source      = "examples/pyspark_pi.py"
    destination = "/tmp/pyspark_pi.py"
  }
  # Removed jupyterlab/onnxserve: no systemd units or user-data copied
  provisioner "file" {
    source      = "harden.sh"
    destination = "/tmp/harden.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo chmod +x /tmp/harden.sh",
      "sudo systemctl daemon-reload",
      "sudo /tmp/harden.sh",
      "sudo install -m 0644 /tmp/spark-java.sh /etc/profile.d/spark-java.sh",
    ]
  }

  # Build all Nix envs + language toolchains in parallel (~6-10 min vs ~25-30 min sequential).
  # All packages pull from cache.nixos.org binary cache so builds are mostly download-bound.
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/nix/flake",
      "sudo mv /tmp/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix flake lock /opt/nix/flake'",
      "sudo chmod +x /tmp/build-base-envs.sh",
      "sudo /tmp/build-base-envs.sh",
      "sudo install -d -m 0755 /usr/share/examples/spark",
      "sudo mv /tmp/pyspark_basic.py /usr/share/examples/spark/pyspark_basic.py",
      "sudo mv /tmp/pyspark_pi.py /usr/share/examples/spark/pyspark_pi.py",
      "sudo chmod 0644 /usr/share/examples/spark/pyspark_*.py",
      # Smoke tests: fail fast if any runtime is missing
      "nix --version",
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py312 -V",
      "/usr/local/bin/py313 -V",
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py312 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "java -version",
      "spark-submit --version",
      "julia -e 'println(VERSION)'",
      "R --version",
      "go version",
      "rustc --version",
      "cargo --version",
      "node --version",
      "echo VERSION=1.0.0-BASE | sudo tee /usr/share/BUILD_INFO",
    ]
  }

  # Package manifest + legal notices + AMI scrub — MUST be the last provisioner
  provisioner "file" {
    source      = "scripts/ami-finalize.sh"
    destination = "/tmp/ami-finalize.sh"
  }
  provisioner "shell" {
    inline = ["sudo chmod +x /tmp/ami-finalize.sh && sudo /tmp/ami-finalize.sh base"]
  }
}

# =======================
# PRO IMAGE (layers on base)
# =======================
# Builds from the already-hardened base AMI — no repeated apt-get, hardening,
# Nix setup, Julia/R/Go/Java/Spark, or base Python env work (~1.5h saved).
# Only adds the pro Python venvs (torch/tf/transformers via pip CPU wheels).
build {
  name    = "cpu-ds-ml-pro"
  sources = ["source.amazon-ebs.ubuntu_pro"]

  # Upload build-pro-envs.sh which creates venvs + pip installs DL packages
  provisioner "file" {
    source      = "scripts/build-pro-envs.sh"
    destination = "/tmp/build-pro-envs.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo chmod +x /tmp/build-pro-envs.sh",
      # build-pro-envs.sh: venv --system-site-packages on base Nix envs,
      # then pip install torch/tf/transformers CPU wheels (~15-20 min total)
      "sudo /tmp/build-pro-envs.sh",
      # Smoke tests
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py312 -V",
      "/usr/local/bin/py313 -V",
      "/usr/local/bin/py311 -c 'import torch, tensorflow, transformers; print(torch.__version__, tensorflow.__version__)'",
      "/usr/local/bin/py312 -c 'import torch, tensorflow, transformers; print(torch.__version__, tensorflow.__version__)'",
      "/usr/local/bin/py313 -c 'import torch, tensorflow, transformers; print(torch.__version__, tensorflow.__version__)'",
      "java -version",
      "spark-submit --version",
      "echo VERSION=1.0.0-PRO | sudo tee /usr/share/BUILD_INFO",
    ]
  }

  # Package manifest + legal notices + AMI scrub — MUST be the last provisioner
  provisioner "file" {
    source      = "scripts/ami-finalize.sh"
    destination = "/tmp/ami-finalize.sh"
  }
  provisioner "shell" {
    inline = ["sudo chmod +x /tmp/ami-finalize.sh && sudo /tmp/ami-finalize.sh pro"]
  }
}

# c6i.xlarge: 4 vCPU / 8 GB — 2x faster Nix builds vs m6i.large at similar cost.
# Use spot_price="auto" in vars to cut build cost by ~70% with Spot pricing.
variable "instance_type"    { default = "c6i.xlarge" }
variable "spot_price"       { default = "" }          # set "auto" to use Spot
variable "root_volume_size" { default = 24 }          # extra headroom for Nix store + pip wheels
variable "subnet_id"           { default = "" }
variable "security_group_id"   { default = "" }
variable "associate_public_ip" {
  type    = bool
  default = true
}
variable "encrypt_ebs" {
  type    = bool
  default = true
}
variable "kms_key_id"          { default = "" }
# Comma-separated list of additional regions to copy the AMI into after build.
# Example: ["us-west-2","eu-west-1","ap-southeast-1"]
variable "additional_regions" {
  type    = list(string)
  default = []
}

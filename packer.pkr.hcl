packer {
  required_plugins {
    amazon = { source = "github.com/hashicorp/amazon", version = ">= 1.3.0" }
  }
}

variable "region" { default = "us-east-1" }
locals { base_name = "cpu-ds-ml-ubuntu-2204" }

# -------- Sources (one per AMI so we can set names/descriptions) --------
source "amazon-ebs" "ubuntu_base" {
  region                      = var.region
  ssh_username                = "ubuntu"
  ena_support                 = true
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = var.associate_public_ip

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
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = var.associate_public_ip

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
    owners      = ["099720109477"]
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

  ami_name        = "${local.base_name}-pro-{{timestamp}}"
  ami_description = "CPU DS/ML AMI (Pro) - Ubuntu 22.04, curated DS/ML sets pinned & ready, CIS-style hardened"
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

  # Build the Nix-based Python env for base
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/nix/flake /opt/nix/envs",
      "sudo mv /tmp/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix flake lock /opt/nix/flake'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/base /opt/nix/flake#py-base'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/base-py313 /opt/nix/flake#py-base-py313'",
      "sudo mkdir -p /opt/nix/langs",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/python313 /opt/nix/flake#python313'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/julia /opt/nix/flake#julia'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/R /opt/nix/flake#R'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/go /opt/nix/flake#go'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/java /opt/nix/flake#java'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/spark /opt/nix/flake#spark'",
      "if [ -x /opt/nix/envs/base/bin/python ]; then sudo ln -sf /opt/nix/envs/base/bin/python /usr/local/bin/py311; fi",
      "if [ -x /opt/nix/envs/base-py313/bin/python ]; then sudo ln -sf /opt/nix/envs/base-py313/bin/python /usr/local/bin/py313; elif ls /opt/nix/envs/base-py313/bin/python3.* >/dev/null 2>&1; then sudo ln -sf $(ls /opt/nix/envs/base-py313/bin/python3.* | head -n1) /usr/local/bin/py313; fi",
      "if [ -x /opt/nix/langs/julia/bin/julia ]; then sudo ln -sf /opt/nix/langs/julia/bin/julia /usr/local/bin/julia; fi",
      "if [ -x /opt/nix/langs/R/bin/R ]; then sudo ln -sf /opt/nix/langs/R/bin/R /usr/local/bin/R; fi",
      "if [ -x /opt/nix/langs/R/bin/Rscript ]; then sudo ln -sf /opt/nix/langs/R/bin/Rscript /usr/local/bin/Rscript; fi",
      "if [ -x /opt/nix/langs/go/bin/go ]; then sudo ln -sf /opt/nix/langs/go/bin/go /usr/local/bin/go; fi",
      "if [ -x /opt/nix/langs/java/bin/java ]; then sudo ln -sf /opt/nix/langs/java/bin/java /usr/local/bin/java; fi",
      "if [ -x /opt/nix/langs/spark/bin/spark-submit ]; then sudo ln -sf /opt/nix/langs/spark/bin/spark-submit /usr/local/bin/spark-submit; fi",
      "if [ -x /opt/nix/langs/spark/bin/pyspark ]; then sudo ln -sf /opt/nix/langs/spark/bin/pyspark /usr/local/bin/pyspark; fi",
      "sudo install -d -m 0755 /usr/share/examples/spark",
      "sudo mv /tmp/pyspark_basic.py /usr/share/examples/spark/pyspark_basic.py",
      "sudo mv /tmp/pyspark_pi.py /usr/share/examples/spark/pyspark_pi.py",
      "sudo chmod 0644 /usr/share/examples/spark/pyspark_*.py",
      # Smoke tests: fail fast if runtimes are missing
      "nix --version",
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py313 -V",
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "java -version",
      "spark-submit --version",
      "julia -e 'println(VERSION)'",
      "R --version",
      "go version",
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
# PRO IMAGE (richer)
# =======================
build {
  name    = "cpu-ds-ml-pro"
  sources = ["source.amazon-ebs.ubuntu_pro"]

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

  provisioner "file" {
    source      = "nix/flake.nix"
    destination = "/tmp/flake.nix"
  }
  provisioner "file" {
    source      = "scripts/spark-java.sh"
    destination = "/tmp/spark-java.sh"
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

  # Build the Nix-based Python env for pro
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/nix/flake /opt/nix/envs",
      "sudo mv /tmp/flake.nix /opt/nix/flake/flake.nix",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix flake lock /opt/nix/flake'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/pro /opt/nix/flake#py-pro'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/envs/pro-py313 /opt/nix/flake#py-pro-py313'",
      "sudo mkdir -p /opt/nix/langs",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/python313 /opt/nix/flake#python313'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/julia /opt/nix/flake#julia'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/R /opt/nix/flake#R'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/go /opt/nix/flake#go'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/java /opt/nix/flake#java'",
      "sudo bash -lc 'source /etc/profile.d/nix.sh && nix build -o /opt/nix/langs/spark /opt/nix/flake#spark'",
      "if [ -x /opt/nix/envs/pro/bin/python ]; then sudo ln -sf /opt/nix/envs/pro/bin/python /usr/local/bin/py311; fi",
      "if [ -x /opt/nix/envs/pro-py313/bin/python ]; then sudo ln -sf /opt/nix/envs/pro-py313/bin/python /usr/local/bin/py313; elif ls /opt/nix/envs/pro-py313/bin/python3.* >/dev/null 2>&1; then sudo ln -sf $(ls /opt/nix/envs/pro-py313/bin/python3.* | head -n1) /usr/local/bin/py313; fi",
      "if [ -x /opt/nix/langs/julia/bin/julia ]; then sudo ln -sf /opt/nix/langs/julia/bin/julia /usr/local/bin/julia; fi",
      "if [ -x /opt/nix/langs/R/bin/R ]; then sudo ln -sf /opt/nix/langs/R/bin/R /usr/local/bin/R; fi",
      "if [ -x /opt/nix/langs/R/bin/Rscript ]; then sudo ln -sf /opt/nix/langs/R/bin/Rscript /usr/local/bin/Rscript; fi",
      "if [ -x /opt/nix/langs/go/bin/go ]; then sudo ln -sf /opt/nix/langs/go/bin/go /usr/local/bin/go; fi",
      "if [ -x /opt/nix/langs/java/bin/java ]; then sudo ln -sf /opt/nix/langs/java/bin/java /usr/local/bin/java; fi",
      "if [ -x /opt/nix/langs/spark/bin/spark-submit ]; then sudo ln -sf /opt/nix/langs/spark/bin/spark-submit /usr/local/bin/spark-submit; fi",
      "if [ -x /opt/nix/langs/spark/bin/pyspark ]; then sudo ln -sf /opt/nix/langs/spark/bin/pyspark /usr/local/bin/pyspark; fi",
      "sudo install -d -m 0755 /usr/share/examples/spark",
      "sudo mv /tmp/pyspark_basic.py /usr/share/examples/spark/pyspark_basic.py",
      "sudo mv /tmp/pyspark_pi.py /usr/share/examples/spark/pyspark_pi.py",
      "sudo chmod 0644 /usr/share/examples/spark/pyspark_*.py",
      # Smoke tests: fail fast if runtimes are missing
      "nix --version",
      "/usr/local/bin/py311 -V",
      "/usr/local/bin/py313 -V",
      "/usr/local/bin/py311 -c 'import pyspark; print(pyspark.__version__)'",
      "/usr/local/bin/py313 -c 'import pyspark; print(pyspark.__version__)'",
      "java -version",
      "spark-submit --version",
      "julia -e 'println(VERSION)'",
      "R --version",
      "go version",
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

variable "instance_type" { default = "m6i.large" }
variable "root_volume_size" { default = 16 }
variable "subnet_id" { default = "" }
variable "security_group_id" { default = "" }
variable "associate_public_ip" {
  type = bool
  default = true
}
variable "encrypt_ebs" {
  type = bool
  default = true
}
variable "kms_key_id" { default = "" }

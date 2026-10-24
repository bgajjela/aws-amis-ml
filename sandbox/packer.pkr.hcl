# SPDX-License-Identifier: Apache-2.0
# Separate sandbox image pipeline. Existing root Packer targets are unchanged.

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.7.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "base_ami_id" {
  type        = string
  description = "Existing CPU DS/ML Ubuntu 22.04 AMI to harden as a sandbox guest"
  default     = ""
  validation {
    condition     = can(regex("^ami-[0-9a-fA-F]+$", var.base_ami_id))
    error_message = "Base AMI ID must be explicit, for example ami-0123456789abcdef0."
  }
}

variable "instance_type" {
  type    = string
  default = "c6i.xlarge"
}

variable "spot_price" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "security_group_id" {
  type    = string
  default = ""
}

variable "associate_public_ip" {
  type    = bool
  default = false
}

variable "root_volume_size" {
  type    = number
  default = 24
}

source "amazon-ebs" "agent_sandbox" {
  region                      = var.region
  source_ami                  = var.base_ami_id
  instance_type               = var.instance_type
  ssh_username                = "ubuntu"
  spot_price                  = var.spot_price
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  security_group_id           = var.security_group_id != "" ? var.security_group_id : null
  associate_public_ip_address = var.associate_public_ip

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name        = "cpu-ds-ml-ubuntu-2204-agent-sandbox-{{timestamp}}"
  ami_description = "Separate agent sandbox guest image layered from the CPU DS/ML Ubuntu 22.04 AMI"
  tags = {
    Name    = "cpu-ds-ml-agent-sandbox"
    Role    = "agent-sandbox"
    Source  = var.base_ami_id
    Profile = "kernel-restricted"
  }
}

build {
  name    = "agent-sandbox"
  sources = ["source.amazon-ebs.agent_sandbox"]

  provisioner "file" {
    source      = "harden-agent-sandbox.sh"
    destination = "/tmp/harden-agent-sandbox.sh"
  }

  provisioner "file" {
    source      = "verify-agent-sandbox.sh"
    destination = "/tmp/verify-agent-sandbox.sh"
  }

  provisioner "file" {
    source      = "agent-sandbox.service"
    destination = "/tmp/agent-sandbox.service"
  }

  provisioner "file" {
    source      = "agent-sandbox-exec"
    destination = "/tmp/agent-sandbox-exec"
  }

  provisioner "file" {
    source      = "adversarial-agent-sim.sh"
    destination = "/tmp/adversarial-agent-sim.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash {{ .Path }}"
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils auditd libcap2-bin util-linux",
      "sudo install -m 0755 /tmp/harden-agent-sandbox.sh /usr/local/sbin/harden-agent-sandbox",
      "sudo install -m 0755 /tmp/verify-agent-sandbox.sh /usr/local/sbin/verify-agent-sandbox",
      "sudo install -m 0755 /tmp/agent-sandbox-exec /usr/local/libexec/agent-sandbox-exec",
      "sudo install -m 0755 /tmp/adversarial-agent-sim.sh /usr/local/sbin/adversarial-agent-sim",
      "sudo install -m 0644 /tmp/agent-sandbox.service /etc/systemd/system/agent-sandbox@.service",
      "sudo /usr/local/sbin/harden-agent-sandbox",
      "sudo /usr/local/sbin/verify-agent-sandbox",
      "sudo /usr/local/sbin/adversarial-agent-sim",
      "sudo rm -f /tmp/harden-agent-sandbox.sh /tmp/verify-agent-sandbox.sh /tmp/agent-sandbox.service /tmp/agent-sandbox-exec /tmp/adversarial-agent-sim.sh",
      "sudo mkdir -p /usr/share/agent-sandbox && printf 'SOURCE_AMI=%s\\nPROFILE=kernel-restricted\\n' '${var.base_ami_id}' | sudo tee /usr/share/agent-sandbox/BUILD_INFO",
    ]
  }
}

.DEFAULT_GOAL := help
SHELL := bash -euo pipefail

PKFLAGS ?=

.PHONY: help init validate fmt build verify shellcheck adversarial

help:
	@echo "Agent Sandbox AMI"
	@echo "  init       packer init"
	@echo "  validate   packer validate"
	@echo "  fmt        packer fmt"
	@echo "  build      build from -var base_ami_id=ami-..."
	@echo "  shellcheck validate shell scripts"
	@echo "  verify     run static verifier locally"
	@echo "  adversarial run safe hostile-agent boundary probes"

init:
	packer init .

validate: init
	packer validate $(PKFLAGS) .

fmt:
	packer fmt .

build: validate
	packer build $(PKFLAGS) .

shellcheck:
	shellcheck -S warning *.sh

verify:
	bash verify-agent-sandbox.sh

adversarial:
	bash adversarial-agent-sim.sh

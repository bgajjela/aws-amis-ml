#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Dimenpoint
# test-ami.sh — launch, verify, and tear down a test EC2 instance for an AMI.
#
# Usage: test-ami.sh <AMI_ID> <arch: x86_64|arm64> <tier: base|pro>
#
# Requires: aws CLI configured, jq, ssh, ssh-keyscan
# Creates a temporary key pair and security group in the default VPC.
# Always cleans up EC2 resources via trap EXIT — safe to interrupt.
set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
AMI_ID="${1:?Usage: $0 <AMI_ID> <x86_64|arm64> <base|pro>}"
ARCH="${2:-x86_64}"
TIER="${3:-base}"

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STAMP=$(date +%s)
KEY_NAME="ami-test-${STAMP}"
INSTANCE_ID=""
TMP_SG_ID=""
KEY_FILE="/tmp/${KEY_NAME}.pem"
KNOWN_HOSTS_FILE="/tmp/known_hosts_${STAMP}"

# ── Cleanup (always runs on exit) ─────────────────────────────────────────────
cleanup() {
  echo "--- cleanup ---"
  if [[ -n "$INSTANCE_ID" ]]; then
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
      --query 'TerminatingInstances[0].CurrentState.Name' --output text 2>/dev/null || true
    echo "Terminating $INSTANCE_ID"
    # Wait for termination so the SG can be deleted (SG deletion fails while attached)
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION" \
      --cli-read-timeout 120 2>/dev/null || true
  fi
  aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION" 2>/dev/null || true
  if [[ -n "$TMP_SG_ID" ]]; then
    aws ec2 delete-security-group --group-id "$TMP_SG_ID" --region "$REGION" 2>/dev/null || true
  fi
  rm -f "$KEY_FILE" "$KNOWN_HOSTS_FILE"
}
trap cleanup EXIT

# ── Networking ────────────────────────────────────────────────────────────────
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text --region "$REGION")

SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=defaultForAz,Values=true" \
  --query 'Subnets[0].SubnetId' --output text --region "$REGION")

# Validate checkip response is a bare IPv4 before using it as a CIDR
_RAW_IP=$(curl -sf --max-time 5 https://checkip.amazonaws.com)
if ! [[ "$_RAW_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "ERROR: Unexpected response from checkip.amazonaws.com: '${_RAW_IP}'" >&2
  exit 1
fi
MY_CIDR="${_RAW_IP}/32"
# Mask sensitive network details in CI logs
echo "::add-mask::${REGION}"
echo "::add-mask::${VPC_ID}"
echo "::add-mask::${SUBNET_ID}"
echo "Runner IP: $MY_CIDR"

# ── Temp security group (SSH in from runner only; restricted egress) ──────────
TMP_SG_ID=$(aws ec2 create-security-group \
  --group-name "ami-test-${STAMP}" \
  --description "Ephemeral AMI test SG — auto-deleted after test run" \
  --vpc-id "$VPC_ID" --region "$REGION" \
  --query 'GroupId' --output text)
echo "::add-mask::${TMP_SG_ID}"

# Inbound: SSH from this runner only
aws ec2 authorize-security-group-ingress \
  --group-id "$TMP_SG_ID" --protocol tcp --port 22 --cidr "$MY_CIDR" \
  --region "$REGION" > /dev/null

# Outbound: revoke default allow-all, then permit only what ami-scan needs
aws ec2 revoke-security-group-egress \
  --group-id "$TMP_SG_ID" --region "$REGION" \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' \
  2>/dev/null || true
aws ec2 authorize-security-group-egress \
  --group-id "$TMP_SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 \
  --region "$REGION" > /dev/null
aws ec2 authorize-security-group-egress \
  --group-id "$TMP_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  --region "$REGION" > /dev/null
aws ec2 authorize-security-group-egress \
  --group-id "$TMP_SG_ID" --protocol udp --port 53 --cidr 0.0.0.0/0 \
  --region "$REGION" > /dev/null

# ── Temp key pair (created mode 0600 from the start via umask) ────────────────
(umask 077; aws ec2 create-key-pair \
  --key-name "$KEY_NAME" --region "$REGION" \
  --query 'KeyMaterial' --output text > "$KEY_FILE")

# ── Instance type ─────────────────────────────────────────────────────────────
if [[ "$ARCH" == "arm64" ]]; then
  INSTANCE_TYPE="c7g.xlarge"
else
  INSTANCE_TYPE="c6i.xlarge"
fi

# ── Launch ────────────────────────────────────────────────────────────────────
echo "Launching ${INSTANCE_TYPE} from ${AMI_ID} (arch=${ARCH} tier=${TIER})..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$TMP_SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --metadata-options 'HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ami-test-${STAMP}},{Key=Purpose,Value=ami-ci-test}]" \
  --region "$REGION" \
  --query 'Instances[0].InstanceId' --output text)

echo "Waiting for $INSTANCE_ID to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
# Mask IP and instance ID from CI logs
echo "::add-mask::${PUBLIC_IP}"
echo "::add-mask::${INSTANCE_ID}"
echo "Instance running at ***"

# ── Capture host key, then enforce it for all subsequent SSH connections ───────
# ssh-keyscan collects the real host key while the instance is initialising;
# StrictHostKeyChecking=yes then ensures every SSH command talks to that exact
# host — an MITM would present a different key and be rejected.
echo "Capturing host key..."
MAX_RETRIES=18
for i in $(seq 1 $MAX_RETRIES); do
  if ssh-keyscan -T 5 "$PUBLIC_IP" >> "$KNOWN_HOSTS_FILE" 2>/dev/null \
    && [[ -s "$KNOWN_HOSTS_FILE" ]]; then
    break
  fi
  if [[ $i -eq $MAX_RETRIES ]]; then
    echo "ERROR: SSH host key not available after $((MAX_RETRIES * 10)) seconds"
    exit 1
  fi
  echo "  retry $i/${MAX_RETRIES}..."
  sleep 10
done

SSH_OPTS="-i ${KEY_FILE} -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=${KNOWN_HOSTS_FILE} \
  -o ConnectTimeout=10 -o BatchMode=yes"

# ── Base runtime verification ─────────────────────────────────────────────────
echo "=== Base runtime verification ==="
# shellcheck disable=SC2086
ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s << 'SSHEOF'
set -euo pipefail

echo "--- Python ---"
/usr/local/bin/py311 -V
/usr/local/bin/py312 -V
/usr/local/bin/py313 -V

echo "--- PySpark imports (all 3 Pythons) ---"
/usr/local/bin/py311 -c "import pyspark; print('PySpark', pyspark.__version__)"
/usr/local/bin/py312 -c "import pyspark; print('PySpark', pyspark.__version__)"
/usr/local/bin/py313 -c "import pyspark; print('PySpark', pyspark.__version__)"

echo "--- Layered base-package imports (all 3 Pythons) ---"
/usr/local/bin/py311 -c "import jupyterlab, onnxruntime, cv2, skimage; print('py311 layered wheels OK')"
/usr/local/bin/py312 -c "import jupyterlab, onnxruntime, cv2, skimage; print('py312 layered wheels OK')"
/usr/local/bin/py313 -c "import jupyterlab, onnxruntime, cv2, skimage; print('py313 layered wheels OK')"

echo "--- Java / Spark ---"
java -version
spark-submit --version 2>&1 | head -2

echo "--- Other runtimes ---"
julia -e 'println("Julia ", VERSION)'
R --version | head -1
go version
rustc --version
node --version

echo "--- Hardening spot checks ---"
# SSH: password auth disabled
grep -i 'passwordauthentication no' /etc/ssh/sshd_config
# UFW active
sudo ufw status | grep -i 'Status: active'
# AppArmor enforcing
sudo aa-status 2>/dev/null | grep -i 'profiles are in enforce mode'

echo "--- Build info ---"
cat /usr/share/BUILD_INFO 2>/dev/null || true
SSHEOF

# ── Pro ML stack verification ─────────────────────────────────────────────────
if [[ "$TIER" == "pro" ]]; then
  echo "=== Pro ML stack verification ==="
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" bash -s << 'SSHEOF'
set -euo pipefail

echo "--- ML stack imports + minimal compute ---"
for PY in /usr/local/bin/py311 /usr/local/bin/py312 /usr/local/bin/py313; do
  $PY -c "
import torch, xgboost, lightgbm, mlflow
x = torch.randn(64, 64); _ = x @ x.T
print('PyTorch', torch.__version__, '(matmul OK)')
print('XGBoost', xgboost.__version__)
print('LightGBM', lightgbm.__version__)
print('MLflow', mlflow.__version__)
"
done

echo "--- TensorFlow + Transformers ---"
/usr/local/bin/py311 -c "
import tensorflow as tf, transformers
x = tf.constant([[1., 2.], [3., 4.]]); _ = tf.linalg.matmul(x, x)
print('TensorFlow', tf.__version__, '(matmul OK)')
print('Transformers', transformers.__version__)
"
/usr/local/bin/py312 -c "import tensorflow as tf; print('TF py312', tf.__version__)"
SSHEOF
fi

# ── CVE scan ──────────────────────────────────────────────────────────────────
echo "=== AMI CVE scan (Trivy) ==="
# shellcheck disable=SC2086
ssh $SSH_OPTS "ubuntu@${PUBLIC_IP}" sudo ami-scan --cve

echo ""
echo "=== All tests passed for ${AMI_ID} (arch=${ARCH} tier=${TIER}) ==="

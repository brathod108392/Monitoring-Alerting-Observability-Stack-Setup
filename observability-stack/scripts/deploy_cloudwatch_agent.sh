#!/bin/bash
# deploy_cloudwatch_agent.sh
# Installs and configures the CloudWatch agent on a production EC2 instance
# Requires: IAM role with CloudWatchAgentServerPolicy attached to the instance
# Usage: sudo bash deploy_cloudwatch_agent.sh

set -euo pipefail

CONFIG_S3_BUCKET="${CW_CONFIG_BUCKET:-prod-observability-configs}"
CONFIG_S3_KEY="cloudwatch/cloudwatch-agent.json"
LOCAL_CONFIG="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
REGION="${AWS_DEFAULT_REGION:-ap-south-1}"

echo "==> Deploying CloudWatch Agent"
echo "    Region : ${REGION}"

# ── Install Agent ──────────────────────────────────────────────────────────────

if ! command -v amazon-cloudwatch-agent-ctl &>/dev/null; then
  echo "==> Downloading CloudWatch agent package..."
  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    PKG_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
  else
    PKG_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb"
  fi

  TMP_DEB=$(mktemp --suffix=.deb)
  curl -sSL "$PKG_URL" -o "$TMP_DEB"
  dpkg -i "$TMP_DEB"
  rm -f "$TMP_DEB"
  echo "  Agent installed"
else
  echo "  CloudWatch agent already installed, skipping download"
fi

# ── Deploy Config ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOCAL_REPO_CONFIG="${REPO_ROOT}/cloudwatch/cloudwatch-agent.json"

if [[ -f "$LOCAL_REPO_CONFIG" ]]; then
  echo "==> Copying config from repo..."
  mkdir -p "$(dirname "$LOCAL_CONFIG")"
  cp "$LOCAL_REPO_CONFIG" "$LOCAL_CONFIG"
else
  echo "==> Fetching config from S3: s3://${CONFIG_S3_BUCKET}/${CONFIG_S3_KEY}"
  aws s3 cp "s3://${CONFIG_S3_BUCKET}/${CONFIG_S3_KEY}" "$LOCAL_CONFIG" --region "$REGION"
fi

# ── Validate & Start ───────────────────────────────────────────────────────────

echo "==> Validating config..."
amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c "file:${LOCAL_CONFIG}" -s

echo "==> Starting CloudWatch agent..."
amazon-cloudwatch-agent-ctl -a start

sleep 3

STATUS=$(amazon-cloudwatch-agent-ctl -a status | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))")
echo ""
echo "==> CloudWatch Agent deployed"
echo "    Config  : ${LOCAL_CONFIG}"
echo "    Status  : ${STATUS}"
echo "    Logs    : /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"

if [[ "$STATUS" != "running" ]]; then
  echo ""
  echo "  WARNING: Agent is not running. Check logs:"
  echo "    tail -50 /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  exit 1
fi

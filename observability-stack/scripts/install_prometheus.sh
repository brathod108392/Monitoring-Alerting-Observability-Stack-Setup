#!/bin/bash
# install_prometheus.sh
# Installs Prometheus on a dedicated EC2 instance (Ubuntu 22.04)
# Run as: sudo bash install_prometheus.sh

set -euo pipefail

PROMETHEUS_VERSION="2.48.0"
INSTALL_DIR="/opt/prometheus"
CONFIG_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"
USER="prometheus"

echo "==> Installing Prometheus ${PROMETHEUS_VERSION}"

# Create prometheus user
if ! id "$USER" &>/dev/null; then
  useradd --no-create-home --shell /bin/false "$USER"
  echo "  Created user: $USER"
fi

# Create directories
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$INSTALL_DIR"

# Download and extract
ARCHIVE="prometheus-${PROMETHEUS_VERSION}.linux-amd64"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "==> Downloading Prometheus..."
curl -sSL "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${ARCHIVE}.tar.gz" \
  -o prometheus.tar.gz

tar -xzf prometheus.tar.gz

# Install binaries
cp "${ARCHIVE}/prometheus"   /usr/local/bin/
cp "${ARCHIVE}/promtool"     /usr/local/bin/
cp -r "${ARCHIVE}/consoles"          "$CONFIG_DIR/"
cp -r "${ARCHIVE}/console_libraries" "$CONFIG_DIR/"

# Set permissions
chown -R "$USER:$USER" "$CONFIG_DIR" "$DATA_DIR"
chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Copy config files from repo (assumes script is run from repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "${REPO_ROOT}/prometheus/prometheus.yml" ]]; then
  cp "${REPO_ROOT}/prometheus/prometheus.yml" "$CONFIG_DIR/"
  cp -r "${REPO_ROOT}/prometheus/rules"   "$CONFIG_DIR/"
  cp -r "${REPO_ROOT}/prometheus/targets" "$CONFIG_DIR/"
  chown -R "$USER:$USER" "$CONFIG_DIR"
  echo "  Copied Prometheus config from repo"
else
  echo "  WARNING: prometheus.yml not found in repo. Copy manually."
fi

# Validate config
echo "==> Validating configuration..."
promtool check config "$CONFIG_DIR/prometheus.yml"

# Create systemd service
cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus Monitoring
Documentation=https://prometheus.io/docs/
Wants=network-online.target
After=network-online.target

[Service]
User=${USER}
Group=${USER}
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/prometheus \\
  --config.file=${CONFIG_DIR}/prometheus.yml \\
  --storage.tsdb.path=${DATA_DIR} \\
  --storage.tsdb.retention.time=30d \\
  --web.enable-lifecycle \\
  --web.enable-admin-api \\
  --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "==> Prometheus installed successfully"
echo "    Version : ${PROMETHEUS_VERSION}"
echo "    Config  : ${CONFIG_DIR}/prometheus.yml"
echo "    Data    : ${DATA_DIR}"
echo "    UI      : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo ""
echo "    Status  : $(systemctl is-active prometheus)"

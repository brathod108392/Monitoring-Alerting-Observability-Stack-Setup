#!/bin/bash
# install_node_exporter.sh
# Installs Prometheus node_exporter on a production server (Ubuntu 22.04)
# Run on each of the 8 production EC2 instances
# Usage: sudo bash install_node_exporter.sh

set -euo pipefail

NODE_EXPORTER_VERSION="1.7.0"
USER="node_exporter"

echo "==> Installing node_exporter ${NODE_EXPORTER_VERSION}"

# Create dedicated user
if ! id "$USER" &>/dev/null; then
  useradd --no-create-home --shell /bin/false "$USER"
fi

# Download and install
ARCHIVE="node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

curl -sSL \
  "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${ARCHIVE}.tar.gz" \
  -o node_exporter.tar.gz

tar -xzf node_exporter.tar.gz
cp "${ARCHIVE}/node_exporter" /usr/local/bin/
chown "$USER:$USER" /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${USER}
Group=${USER}
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/node_exporter \\
  --collector.systemd \\
  --collector.processes \\
  --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)" \\
  --web.listen-address=0.0.0.0:9100

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Open port 9100 in ufw (if active)
if ufw status | grep -q "Status: active"; then
  # Allow only from Prometheus server IP
  PROMETHEUS_IP="${PROMETHEUS_SERVER_IP:-10.0.0.5}"
  ufw allow from "$PROMETHEUS_IP" to any port 9100 comment "Prometheus scrape"
  echo "  UFW rule added: allow $PROMETHEUS_IP → port 9100"
fi

rm -rf "$TMP_DIR"

echo ""
echo "==> node_exporter installed"
echo "    Version  : ${NODE_EXPORTER_VERSION}"
echo "    Endpoint : http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo "    Status   : $(systemctl is-active node_exporter)"

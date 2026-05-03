# Observability Stack — FinTech Production Environment

A full observability stack built for a FinTech startup's production environment. Prior to this engagement, the client had no metrics collection, no alerting, and no log aggregation. A payment processing outage went undetected for **47 minutes**, prompting this implementation.

---

## Stack Overview

| Layer | Tool | Purpose |
|---|---|---|
| Metrics | Prometheus | Scrape & store time-series metrics |
| Dashboards | Grafana | Visualise infra, app, and business metrics |
| Alerting | AlertManager + PagerDuty/Slack | Route and deliver alerts |
| Log Aggregation | AWS CloudWatch Logs | Centralised log pipeline |
| Uptime Monitoring | CloudWatch Synthetics | API endpoint canary checks |

---

## Architecture

```
8x Production EC2 Instances
        │
        ├── node_exporter (port 9100)
        ├── app_exporter  (port 9101)
        └── cloudwatch-agent → CloudWatch Logs
                │
                ▼
        Prometheus EC2 (dedicated)
        ├── Scrapes all exporters every 15s
        ├── Evaluates 22 alert rules
        └── Fires to AlertManager
                │
                ├── Critical → PagerDuty
                └── Non-critical → Slack

        Grafana EC2 (or same as Prometheus)
        └── Queries Prometheus → 3 dashboard groups

        CloudWatch Synthetics
        └── 5 canary checks on critical API endpoints
```

---

## Directory Structure

```
.
├── prometheus/
│   ├── prometheus.yml          # Main Prometheus config
│   ├── rules/
│   │   ├── infrastructure.yml  # CPU, memory, disk, network rules
│   │   └── application.yml     # Error rate, latency, service-down rules
│   └── targets/
│       └── ec2_targets.yml     # Static target definitions for 8 servers
├── alertmanager/
│   └── alertmanager.yml        # Routing: PagerDuty (critical) / Slack (warning)
├── grafana/
│   └── dashboards/
│       ├── infrastructure.json # CPU, memory, disk, network panels
│       ├── application.json    # Request rate, error rate, latency panels
│       └── business.json       # Transaction success rate, payment metrics
├── cloudwatch/
│   ├── cloudwatch-agent.json   # CloudWatch agent config for all servers
│   ├── log-filters/
│   │   └── metric_filters.tf   # Terraform for CloudWatch metric filters
│   └── synthetics/
│       └── canary.js           # Canary script for API endpoint checks
├── scripts/
│   ├── install_node_exporter.sh
│   ├── install_prometheus.sh
│   └── deploy_cloudwatch_agent.sh
└── docs/
    └── runbook.md              # Alert runbook: severity, escalation, resolution
```

---

## Results

- **MTTD reduced** from 47 minutes → under 3 minutes
- **22 alert rules** deployed across infra + application layers
- **0 false positives** in first 4 weeks of operation
- **3 slow DB queries** identified and resolved within the first week via Grafana dashboards

---

## Setup

See individual component READMEs and [`docs/runbook.md`](docs/runbook.md) for full setup and operational procedures.

### Quick Start (Prometheus + AlertManager)

```bash
# 1. Install Prometheus on dedicated EC2
./scripts/install_prometheus.sh

# 2. Deploy node_exporter on all 8 production servers
./scripts/install_node_exporter.sh

# 3. Deploy CloudWatch agent
./scripts/deploy_cloudwatch_agent.sh

# 4. Start Prometheus with config
prometheus --config.file=prometheus/prometheus.yml

# 5. Start AlertManager
alertmanager --config.file=alertmanager/alertmanager.yml
```

---

## Alert Routing

| Severity | Condition | Destination |
|---|---|---|
| Critical | Service down, error rate > 5%, disk > 95% | PagerDuty (immediate page) |
| Warning | CPU > 85%, disk > 80%, error rate > 1% | Slack `#alerts-infra` |
| Info | Elevated latency, non-critical threshold breach | Slack `#alerts-info` |

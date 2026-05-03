# Observability Runbook — FinTech Production

**Last updated:** November 2024
**Owner:** Infrastructure & DevOps
**Scope:** All 22 alert conditions deployed across the Prometheus + CloudWatch observability stack

---

## Alert Severity Levels

| Severity | Response Time | Channel | Escalation |
|---|---|---|---|
| **Critical** | Immediate (< 5 min) | PagerDuty + Slack #alerts-critical | On-call engineer paged |
| **Warning** | Within 30 minutes | Slack #alerts-infra / #alerts-app | Acknowledge and resolve during business hours |
| **Info** | Best effort | Slack #alerts-info | No escalation required |

---

## Escalation Path

```
Alert fires
    │
    ▼
On-call engineer (PagerDuty page)
    │  No acknowledgement within 10 min
    ▼
Senior Engineer (secondary on-call)
    │  No acknowledgement within 20 min
    ▼
Engineering Lead
    │  Incident ongoing > 30 min
    ▼
Incident declared — war room convened
```

---

## Alert Runbooks

---

### `HighCPUUsage` / `CriticalCPUUsage`

**Trigger:** CPU > 85% for 5 minutes (warning) or > 95% for 2 minutes (critical)

**Likely causes:**
- Traffic spike — check request rate in Grafana Application dashboard
- Runaway process — memory leak or infinite loop in application
- Background job — scheduled batch job consuming resources
- Crypto miner / intrusion (rare but check)

**Investigation steps:**
1. SSH into the affected instance: `ssh -i ~/.ssh/prod.pem ubuntu@<instance-ip>`
2. Check top consumers: `top -b -n1 | head -20` or `htop`
3. Check recent deploys: `journalctl -u app --since "30 minutes ago"`
4. Check request rate: Grafana → Application Metrics → Request Rate panel
5. Check for cronjobs: `crontab -l && cat /etc/cron.d/*`

**Resolution:**
- If traffic spike: scale horizontally (launch additional EC2 from AMI, add to load balancer)
- If runaway process: `kill -9 <pid>` after identifying the process, then investigate root cause
- If batch job: reschedule to off-peak hours (post-midnight IST)

---

### `HighMemoryUsage` / `CriticalMemoryUsage`

**Trigger:** Memory > 85% for 5 minutes (warning) or > 95% for 2 minutes (critical)

**Likely causes:**
- Memory leak in application — usage grows over time without releasing
- Insufficient instance size for current traffic
- Large in-memory cache not evicting entries

**Investigation steps:**
1. `free -h` — check available memory
2. `ps aux --sort=-%mem | head -10` — find top memory consumers
3. Check application logs for OOM warnings: `grep -i "out of memory\|oom" /var/log/application/app.log`
4. Compare memory trend in Grafana (is it growing steadily or sudden spike?)

**Resolution:**
- Memory leak: restart the application service (`systemctl restart app`), create ticket for dev team
- Sustained growth: escalate to dev team to investigate leak; consider instance upsize
- OOM kill already occurred: check `dmesg | grep -i "oom"` for killed processes; restart affected services

---

### `DiskSpaceWarning` / `DiskSpaceCritical` / `DiskWillFillIn4Hours`

**Trigger:** Disk > 80% (warning), > 95% (critical), or projected full within 4 hours

**Likely causes:**
- Application logs not rotating
- Database WAL / transaction logs accumulating
- Core dumps from application crashes
- Large temporary files not cleaned up

**Investigation steps:**
1. `df -h` — identify which filesystem is filling
2. `du -sh /* 2>/dev/null | sort -rh | head -20` — find large directories
3. Check logs: `du -sh /var/log/* | sort -rh | head -10`
4. Find large files: `find / -size +500M -type f 2>/dev/null`

**Resolution:**
- Logs: `journalctl --vacuum-size=500M` or truncate old log files
- Rotate logs immediately: `logrotate -f /etc/logrotate.conf`
- Temp files: `rm -rf /tmp/* /var/tmp/*` (verify safe first)
- Long term: adjust log retention policy, add EBS volume, or enable log shipping to S3

---

### `InstanceDown` / `NodeExporterDown`

**Trigger:** Instance unreachable for > 1 minute

**Likely causes:**
- EC2 instance has crashed or been terminated
- node_exporter process has died
- Network ACL / security group change blocking scrape port (9100)
- Instance is under heavy load and not responding

**Investigation steps:**
1. Check AWS Console: EC2 → Instances → verify instance state
2. Check system status checks in AWS Console
3. If instance is running, SSH in and check node_exporter: `systemctl status node_exporter`
4. Check CloudWatch metrics for the instance (pre-exporter data still available)
5. Review VPC security groups for port 9100

**Resolution:**
- node_exporter dead: `systemctl restart node_exporter`
- Instance crashed: reboot via AWS Console or `aws ec2 reboot-instances --instance-ids <id>`
- Instance terminated: launch replacement from AMI, re-register in targets file

---

### `HighErrorRate` / `CriticalErrorRate`

**Trigger:** HTTP 5xx error rate > 1% for 3 min (warning) or > 5% for 1 min (critical)

**Likely causes:**
- Recent code deployment with a bug
- Downstream dependency (database, external API) is unavailable
- Resource exhaustion (out of DB connections, memory, file handles)
- Bad configuration deployed

**Investigation steps:**
1. Check error logs: `tail -200 /var/log/application/error.log`
2. Check recent deploys: `git log --oneline -10` on the app server
3. Check DB connectivity: `systemctl status postgresql` or relevant DB service
4. Check Grafana → Application → DB Connection Pool panel
5. Check if error rate correlates with a specific endpoint using access logs

**Resolution:**
- Bad deploy: roll back (`git revert`, redeploy, or deploy previous AMI)
- DB down: see `SlowDatabaseQueries` / `DatabaseConnectionPoolExhausted` below
- External API: check third-party status pages; implement circuit breaker if not already present

---

### `PaymentServiceDown`

**Trigger:** Payment service endpoint unreachable for > 30 seconds

**CRITICAL — Payment processing is impacted. Treat as P1 incident immediately.**

**Investigation steps:**
1. Check payment service process: `systemctl status payment-service`
2. Check logs: `journalctl -u payment-service --since "10 minutes ago"`
3. Verify DB connectivity from payment server
4. Check if CloudWatch Synthetics canary for `/v1/payments/ping` is also failing

**Resolution:**
1. If process dead: `systemctl restart payment-service`
2. If restart fails: check logs for startup errors, escalate to dev team immediately
3. Communicate to stakeholders if downtime exceeds 2 minutes
4. Document incident timeline for post-mortem

---

### `LowPaymentSuccessRate`

**Trigger:** Payment transaction success rate < 99%

**Investigation steps:**
1. Check payment logs for failure reasons: `grep "PAYMENT_FAILED" /var/log/application/payment.log | tail -50`
2. Look for patterns — specific bank, payment method, or amount range failing
3. Check external payment gateway status page
4. Review DB for failed transaction records

**Resolution:**
- Gateway issue: contact payment gateway support; switch to fallback gateway if available
- Application bug: escalate to dev team; consider pausing new payment acceptance if failure rate > 10%

---

### `HighP95Latency` / `HighP99Latency`

**Trigger:** p95 latency > 1s for 5 min (warning) or p99 > 2s for 3 min (critical)

**Investigation steps:**
1. Open Grafana → Application → Latency panel — identify which service/endpoint
2. Check DB query latency panel — often the root cause
3. Check CPU and memory on affected instance
4. Check for traffic spikes that coincide with latency increase

**Resolution:**
- DB slow queries: see `SlowDatabaseQueries` below
- Resource pressure: scale instance or add horizontal capacity
- Application issue: check for N+1 query patterns, missing indexes, inefficient loops

---

### `SlowDatabaseQueries`

**Trigger:** DB query p95 latency > 1 second

**This was the root cause of 3 identified performance issues in the first week of monitoring.**

**Investigation steps:**
1. Check Grafana → Application → DB Query Latency panel (filter by query_type)
2. On DB server, run: `SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;`
3. Check for missing indexes: `SELECT * FROM pg_stat_user_tables WHERE seq_scan > idx_scan;`
4. Check for lock contention: `SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock';`

**Resolution:**
- Missing index: `CREATE INDEX CONCURRENTLY idx_name ON table(column);` (CONCURRENTLY avoids table lock)
- Inefficient query: escalate to dev team with query details and execution plan (`EXPLAIN ANALYZE`)
- Lock contention: identify and terminate blocking queries if safe; investigate root cause

---

### `DatabaseConnectionPoolExhausted`

**Trigger:** Available DB connections < 10% of pool size

**Investigation steps:**
1. `SELECT count(*) FROM pg_stat_activity;` — total active connections
2. `SELECT state, count(*) FROM pg_stat_activity GROUP BY state;` — breakdown by state
3. Check for idle connections being held open (application connection leak)

**Resolution:**
- Immediate: restart application servers to release connections (rolling restart if multiple)
- Long term: implement connection pooling (PgBouncer) if not already in place; review connection leak in application code

---

### CloudWatch Synthetics Canary Failures

**Trigger:** API endpoint response time > 2s or non-2xx response

**Monitored endpoints:**
1. `GET /health` — API gateway health check
2. `GET /v1/payments/ping` — Payment service ping
3. `POST /v1/auth/verify` — Auth token verification
4. `GET /v1/transactions/status` — Transaction status lookup
5. `GET /v1/accounts/balance` — Account balance retrieval

**Investigation steps:**
1. CloudWatch → Synthetics → Canaries → view latest run result and failure screenshot
2. Check which specific endpoint failed and the error message
3. Cross-reference with Prometheus alerts — is the service showing errors there too?

**Resolution:**
- Follow the relevant service runbook above based on which endpoint failed

---

## Post-Incident Checklist

After every P1 / Critical incident:

- [ ] Timeline documented (detection time, acknowledgement time, resolution time)
- [ ] Root cause identified
- [ ] Post-mortem written and shared with team within 48 hours
- [ ] Action items created with owners and due dates
- [ ] Alert thresholds reviewed — did the alert fire at the right time?
- [ ] Runbook updated if steps were unclear or incorrect

---

## Contact Reference

| Role | Name | PagerDuty | Slack |
|---|---|---|---|
| On-call (Primary) | Rotation | Configured in PagerDuty schedule | @oncall |
| Engineering Lead | — | — | @eng-lead |
| DevOps | — | — | @devops |

*Update this table with actual names before go-live.*

/**
 * CloudWatch Synthetics Canary
 * Monitors 5 critical API endpoints for the FinTech production environment.
 *
 * Triggers alert if:
 *   - Response time exceeds 2000ms
 *   - HTTP status is not 2xx
 *   - Connection times out (10s)
 *
 * Schedule: Every 1 minute
 * Region:   ap-south-1
 */

const synthetics = require("Synthetics");
const log = require("SyntheticsLogger");
const https = require("https");

const BASE_URL = "https://api.fintech-prod.internal";
const RESPONSE_TIME_THRESHOLD_MS = 2000;
const REQUEST_TIMEOUT_MS = 10000;

// ── Endpoint Definitions ──────────────────────────────────────────────────────

const ENDPOINTS = [
  {
    name: "health-check",
    path: "/health",
    method: "GET",
    expectedStatus: 200,
    description: "API Gateway health check",
  },
  {
    name: "payment-initiate",
    path: "/v1/payments/ping",
    method: "GET",
    expectedStatus: 200,
    description: "Payment service availability ping",
  },
  {
    name: "auth-token",
    path: "/v1/auth/verify",
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${process.env.CANARY_TEST_TOKEN}`,
    },
    body: JSON.stringify({ check: true }),
    expectedStatus: 200,
    description: "Auth token verification endpoint",
  },
  {
    name: "transaction-status",
    path: "/v1/transactions/status",
    method: "GET",
    headers: {
      Authorization: `Bearer ${process.env.CANARY_TEST_TOKEN}`,
    },
    expectedStatus: 200,
    description: "Transaction status lookup",
  },
  {
    name: "account-balance",
    path: "/v1/accounts/balance",
    method: "GET",
    headers: {
      Authorization: `Bearer ${process.env.CANARY_TEST_TOKEN}`,
    },
    expectedStatus: 200,
    description: "Account balance retrieval",
  },
];

// ── Request Helper ────────────────────────────────────────────────────────────

function makeRequest(endpoint) {
  return new Promise((resolve, reject) => {
    const url = new URL(BASE_URL + endpoint.path);
    const startTime = Date.now();

    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method: endpoint.method || "GET",
      headers: {
        "User-Agent": "CloudWatch-Synthetics-Canary/1.0",
        Accept: "application/json",
        ...(endpoint.headers || {}),
      },
      timeout: REQUEST_TIMEOUT_MS,
    };

    const req = https.request(options, (res) => {
      const responseTime = Date.now() - startTime;
      let body = "";

      res.on("data", (chunk) => {
        body += chunk;
      });

      res.on("end", () => {
        resolve({
          statusCode: res.statusCode,
          responseTime,
          body,
          headers: res.headers,
        });
      });
    });

    req.on("timeout", () => {
      req.destroy();
      reject(new Error(`Request timeout after ${REQUEST_TIMEOUT_MS}ms`));
    });

    req.on("error", (err) => {
      reject(err);
    });

    if (endpoint.body) {
      req.write(endpoint.body);
    }

    req.end();
  });
}

// ── Canary Handler ────────────────────────────────────────────────────────────

const checkEndpoint = async (endpoint) => {
  log.info(`Checking endpoint: ${endpoint.name} → ${endpoint.method} ${endpoint.path}`);

  let result;
  try {
    result = await makeRequest(endpoint);
  } catch (err) {
    const msg = `[FAIL] ${endpoint.name}: Request failed — ${err.message}`;
    log.error(msg);
    throw new Error(msg);
  }

  const { statusCode, responseTime } = result;

  log.info(
    `[${endpoint.name}] Status: ${statusCode} | Response time: ${responseTime}ms`
  );

  // Check status code
  if (statusCode < 200 || statusCode >= 300) {
    const msg = `[FAIL] ${endpoint.name}: Expected 2xx, got ${statusCode}`;
    log.error(msg);
    throw new Error(msg);
  }

  // Check response time
  if (responseTime > RESPONSE_TIME_THRESHOLD_MS) {
    const msg = `[FAIL] ${endpoint.name}: Response time ${responseTime}ms exceeds ${RESPONSE_TIME_THRESHOLD_MS}ms threshold`;
    log.error(msg);
    throw new Error(msg);
  }

  log.info(`[PASS] ${endpoint.name}: ${statusCode} in ${responseTime}ms`);

  // Emit custom metric for response time tracking in Grafana
  await synthetics.executeStep(`record-${endpoint.name}`, async () => {
    synthetics.addExecutionError(null);
  });

  return { endpoint: endpoint.name, statusCode, responseTime };
};

// ── Main Canary Entry Point ───────────────────────────────────────────────────

exports.handler = async () => {
  const results = [];
  const failures = [];

  for (const endpoint of ENDPOINTS) {
    try {
      const result = await checkEndpoint(endpoint);
      results.push({ ...result, status: "pass" });
    } catch (err) {
      failures.push({ endpoint: endpoint.name, error: err.message });
      results.push({ endpoint: endpoint.name, status: "fail", error: err.message });
    }
  }

  log.info("Canary run complete:", JSON.stringify(results, null, 2));

  if (failures.length > 0) {
    const failedNames = failures.map((f) => f.endpoint).join(", ");
    throw new Error(
      `${failures.length}/${ENDPOINTS.length} endpoint(s) failed: ${failedNames}`
    );
  }

  return {
    statusCode: 200,
    body: `All ${ENDPOINTS.length} endpoints passed`,
    results,
  };
};

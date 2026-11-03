// packages/monitoring-contract/normalize.mjs
var identifier = (value) => typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,95}$/.test(value);
var safeKeys = /* @__PURE__ */ new Set(["status", "stage", "attempt", "count", "duration_ms", "http_status", "effect_started", "capability", "pending", "dropped", "reason"]);
function safeContext(input) {
  const result = {};
  if (!input || typeof input !== "object") return result;
  for (const key of Object.keys(input).slice(0, 32).sort()) {
    if (!safeKeys.has(key)) continue;
    const value = input[key];
    if (value === null || typeof value === "boolean" || typeof value === "number" && Number.isFinite(value)) result[key] = value;
    else if (typeof value === "string" && /^[a-zA-Z0-9_.: -]{0,128}$/.test(value)) result[key] = value;
  }
  return result;
}
function normalizeError(error) {
  let name = "Error", stack = "";
  try {
    if (error instanceof Error) {
      if (/^[A-Za-z][A-Za-z0-9]{0,40}$/.test(error.name)) name = error.name;
      stack = String(error.stack ?? "").split("\n").slice(1, 9).map((line) => {
        const match = line.match(/\bat\s+([A-Za-z_$][\w.$]{0,64})/);
        return match ? match[1] : "<frame>";
      }).join("|");
    }
  } catch {
  }
  return { name, stack_signature: stack };
}

// packages/monitoring-client/src/index.ts
function createMonitoring(config) {
  const enabled = config.enabled !== false;
  if (!identifier(config.service) || !identifier(config.release)) throw Error("monitoring_identity_invalid");
  if (enabled) {
    if (!config.baseUrl || !config.token || config.token.length < 24) throw Error("monitoring_configuration_required");
    const url = new URL(config.baseUrl);
    if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash || url.pathname !== "/") throw Error("monitoring_origin_invalid");
  }
  const transport = config.fetch ?? fetch, limit = Math.min(100, Math.max(1, config.maxBuffer ?? 100));
  let buffer = [], dropped = 0, closed = false, inflight, closing;
  const instance = crypto.randomUUID();
  let sequence = 0;
  const diagnostic = (code) => {
    try {
      config.diagnostic?.(code);
    } catch {
    }
  };
  function enqueue(fields) {
    const eventId = crypto.randomUUID(), ticket = { eventId, buffered: false };
    if (!enabled || closed) return ticket;
    try {
      if (!identifier(fields.error_code) || !identifier(fields.operation) || fields.check_id && !identifier(fields.check_id)) throw Error("invalid_report");
      const event = { event_id: eventId, observed_at: Date.now(), service: config.service, release: config.release, ...fields, context: safeContext(fields.context) };
      if (buffer.length >= limit || new TextEncoder().encode(JSON.stringify([...buffer, event])).length > 256 * 1024) {
        const victim = buffer.findIndex((e) => e.kind === "error");
        if (fields.kind !== "error" && victim >= 0) buffer.splice(victim, 1);
        else {
          dropped++;
          diagnostic("buffer_overflow");
          return ticket;
        }
        dropped++;
      }
      buffer.push(event);
      ticket.buffered = true;
    } catch {
      dropped++;
      diagnostic("invalid_report");
    }
    return ticket;
  }
  const result = (receipts, status) => ({ receipts, pending: buffer.length, dropped, status });
  function flush(options = {}) {
    if (inflight) return inflight;
    if (!enabled) return Promise.resolve(result([], "disabled"));
    const deadline = Date.now() + Math.min(1e3, Math.max(1, options.timeoutMs ?? 1e3));
    const batch = [];
    let size = 32;
    for (const event of buffer.slice(0, 50)) {
      const bytes = new TextEncoder().encode(JSON.stringify(event)).length + 1;
      if (size + bytes > 64e3) break;
      size += bytes;
      batch.push(event);
    }
    if (!batch.length) return Promise.resolve(result([], "flushed"));
    inflight = (async () => {
      const receipts = [];
      let rejected = false;
      for (let attempt = 0; attempt < 3 && Date.now() < deadline; attempt++) {
        const controller = new AbortController();
        let timer;
        try {
          const response = await Promise.race([transport(new URL("/v1/observations", config.baseUrl), { method: "POST", redirect: "manual", signal: controller.signal, headers: { Authorization: "Bearer " + config.token, "Content-Type": "application/json" }, body: JSON.stringify({ major: 1, events: batch }) }), new Promise((_, reject) => {
            timer = setTimeout(() => {
              controller.abort();
              reject(Error("timeout"));
            }, Math.max(1, deadline - Date.now()));
          })]);
          if (response.status === 429 || response.status >= 500) throw Error("retry");
          if (response.status !== 202 && response.status !== 409 && response.status !== 400) {
            diagnostic("ingest_rejected");
            break;
          }
          if (timer) clearTimeout(timer);
          const payload = await Promise.race([response.json(), new Promise((_, reject) => {
            timer = setTimeout(() => reject(Error("body_timeout")), Math.max(1, deadline - Date.now()));
          })]);
          const ids = new Set(batch.map((e) => e.event_id)), done = /* @__PURE__ */ new Set();
          for (const item of payload.results ?? []) {
            if (!ids.has(item.eventId)) continue;
            if (item.recorded === true) {
              receipts.push(item);
              done.add(item.eventId);
            } else if ([400, 403, 409, 422].includes(item.status)) {
              rejected = true;
              dropped++;
              done.add(item.eventId);
              diagnostic("event_rejected");
            }
          }
          buffer = buffer.filter((e) => !done.has(e.event_id));
          break;
        } catch {
          if (attempt < 2 && Date.now() + 25 < deadline) await new Promise((resolve) => setTimeout(resolve, 10 + Math.random() * 15));
        } finally {
          if (timer) clearTimeout(timer);
          controller.abort();
        }
      }
      return result(receipts, buffer.length ? receipts.length ? "partial" : "unavailable" : rejected ? "partial" : "flushed");
    })().catch(() => result([], "unavailable")).finally(() => {
      inflight = void 0;
    });
    return inflight;
  }
  return {
    reportError: (error, options) => enqueue({ kind: "error", outcome: "failure", error_code: options.code, operation: options.operation, severity: "warning", ...normalizeError(error), context: options.context }),
    raiseIssue: (key, options) => enqueue({ kind: "condition", outcome: "failure", check_id: key, operation: key, error_code: options.code, severity: options.severity, context: options.context }),
    resolveIssue: (key, proof) => enqueue({ kind: "condition", outcome: "success", check_id: key, operation: key, error_code: "resolved", severity: "warning", incident_id: proof.incidentId, expected_revision: proof.expectedRevision, context: proof.evidence }),
    heartbeat: (key, value) => enqueue({ kind: "heartbeat", outcome: value.status === "ok" ? "success" : "failure", check_id: key, operation: key, error_code: value.code ?? (value.status === "ok" ? "ok" : "check_failed"), severity: "warning", instance, sequence: ++sequence, context: value.context }),
    flush,
    close: (options = {}) => {
      if (closing) return closing;
      closed = true;
      closing = (async () => {
        const until = Date.now() + Math.min(1e3, Math.max(1, options.timeoutMs ?? 1e3));
        const receipts = [];
        if (inflight) receipts.push(...(await inflight).receipts);
        let current = await flush({ timeoutMs: Math.max(1, until - Date.now()) });
        receipts.push(...current.receipts);
        while (current.pending && current.status === "partial" && Date.now() < until) {
          current = await flush({ timeoutMs: Math.max(1, until - Date.now()) });
          receipts.push(...current.receipts);
        }
        return { ...current, receipts };
      })();
      return closing;
    }
  };
}
export {
  createMonitoring
};

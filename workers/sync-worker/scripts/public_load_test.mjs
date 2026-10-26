import { performance } from 'node:perf_hooks';

const url = process.argv[2] ?? 'https://sync.festapp.net/v1/public-sync/9/643/head';
const clients = Number(process.argv[3] ?? 5000);
const windowMs = Number(process.argv[4] ?? 15000);
const timeoutMs = 10000;

if (!Number.isSafeInteger(clients) || clients <= 0 || !Number.isFinite(windowMs) || windowMs <= 0) {
  throw new Error('usage: public_load_test.mjs [url] [clients] [window_ms]');
}

const initialLatencies = [];
const conditionalLatencies = [];
const initialStatuses = new Map();
const conditionalStatuses = new Map();
const errors = [];
const cacheStatuses = new Map();
let responseBytes = 0;

function increment(target, value) {
  target.set(value, (target.get(value) ?? 0) + 1);
}

function percentile(values, fraction) {
  const sorted = [...values].sort((a, b) => a - b);
  return Number(sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)].toFixed(1));
}

async function request(headers, latencies, statuses) {
  const started = performance.now();
  const response = await fetch(url, {
    headers,
    signal: AbortSignal.timeout(timeoutMs),
  });
  latencies.push(performance.now() - started);
  increment(statuses, response.status);
  increment(cacheStatuses, response.headers.get('cf-cache-status') ?? 'unreported');
  responseBytes += (await response.arrayBuffer()).byteLength;
  return response;
}

async function client(index) {
  await new Promise((resolve) => setTimeout(resolve, Math.floor(index * windowMs / clients)));
  try {
    const initial = await request({}, initialLatencies, initialStatuses);
    const etag = initial.headers.get('etag');
    if (!etag) throw new Error('initial response omitted ETag');
    await new Promise((resolve) => setTimeout(resolve, windowMs));
    await request({ 'If-None-Match': etag }, conditionalLatencies, conditionalStatuses);
  } catch (error) {
    errors.push(error instanceof Error ? error.message : String(error));
  }
}

const started = performance.now();
await Promise.all(Array.from({ length: clients }, (_, index) => client(index)));
const durationMs = performance.now() - started;

const result = {
  url,
  clients,
  requests: initialLatencies.length + conditionalLatencies.length,
  duration_ms: Number(durationMs.toFixed(1)),
  average_rps: Number(((initialLatencies.length + conditionalLatencies.length) / (durationMs / 1000)).toFixed(1)),
  initial: {
    statuses: Object.fromEntries(initialStatuses),
    p50_ms: percentile(initialLatencies, 0.50),
    p95_ms: percentile(initialLatencies, 0.95),
    p99_ms: percentile(initialLatencies, 0.99),
  },
  conditional: {
    statuses: Object.fromEntries(conditionalStatuses),
    p50_ms: percentile(conditionalLatencies, 0.50),
    p95_ms: percentile(conditionalLatencies, 0.95),
    p99_ms: percentile(conditionalLatencies, 0.99),
  },
  errors: errors.length,
  sample_errors: [...new Set(errors)].slice(0, 5),
  cache_evidence: {
    cf_cache_statuses: Object.fromEntries(cacheStatuses),
    response_bytes: responseBytes,
    note: 'Synthetic cache headers are operational evidence, not Cloudflare billing truth; confirm R2 reads and cost in the dashboard.',
  },
};

console.log(JSON.stringify(result, null, 2));
if (errors.length || initialStatuses.get(200) !== clients || conditionalStatuses.get(304) !== clients) {
  process.exit(1);
}

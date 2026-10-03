const source = "https://api.cnb.cz/cnbapi/exrates/daily";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export function createRateHandler(deps: {
  authorize: (header: string) => Promise<boolean>;
  fetch?: typeof fetch;
  now?: () => number;
}) {
  let cached: object | undefined;
  let expires = 0;
  let pending: Promise<object> | undefined;
  const now = deps.now ?? Date.now;
  const reply = (status: number, body: object) => new Response(JSON.stringify(body), {
    status, headers: {...cors, "Content-Type": "application/json", "Cache-Control": "no-store"},
  });
  async function load() {
    const response = await (deps.fetch ?? fetch)(source, {
      signal: AbortSignal.timeout(8000), redirect: "error",
    });
    if (!response.ok) throw new Error("Unavailable rates");
    const text = await response.text();
    if (text.length > 64000) throw new Error("Invalid rates");
    const rows = JSON.parse(text).rates;
    if (!Array.isArray(rows) || rows.length === 0 || rows.length > 100) throw new Error("Invalid rates");
    const date = rows[0].validFor;
    if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        !Number.isFinite(Date.parse(date)) ||
        now() - Date.parse(date) > 7 * 86400000 || Date.parse(date) > now() + 86400000) throw new Error("Stale rates");
    const rates: Record<string, {amount: string; rate: string}> = {CZK: {amount: "1", rate: "1"}};
    for (const row of rows) {
      if (row.validFor !== date || !/^[A-Z]{3}$/.test(row.currencyCode) ||
          !Number.isSafeInteger(row.amount) || row.amount <= 0 ||
          typeof row.rate !== "number" || !Number.isFinite(row.rate) || row.rate <= 0 ||
          !/^\d+(\.\d{1,6})?$/.test(String(row.rate))) throw new Error("Invalid rate");
      if (rates[row.currencyCode]) throw new Error("Duplicate rate");
      rates[row.currencyCode] = {amount: String(row.amount), rate: String(row.rate)};
    }
    cached = {date, source: "CNB", base: "CZK", rates};
    expires = now() + 3600000;
    return cached;
  }
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response("ok", {headers: cors});
    if (request.method !== "POST") return reply(405, {error: "Method not allowed"});
    const header = request.headers.get("Authorization") ?? "";
    if (!/^Bearer [^\s]+$/i.test(header)) return reply(401, {error: "Unauthorized"});
    try {
      if (!await deps.authorize(header)) return reply(401, {error: "Unauthorized"});
      if (cached && now() < expires) return reply(200, cached);
      if (!pending) pending = load().finally(() => { pending = undefined; });
      return reply(200, await pending);
    } catch {
      return reply(503, {error: "Exchange rates unavailable"});
    }
  };
}

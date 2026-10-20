import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { parseMcpTenants } from "./config.ts";
import { handleMcpExchange } from "./handler.ts";
const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  global: { fetch: ((input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) })) as typeof fetch } };
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, options);
const makeAnon = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, options);
let tenants: ReturnType<typeof parseMcpTenants>;
try { tenants = parseMcpTenants(Deno.env.get("FESTAPP_MCP_TENANTS_JSON") ?? "[]"); }
catch { tenants = []; }
Deno.serve(req => {
  if (!tenants.length) return Response.json({ error: "connection_unavailable" }, { status: 503 });
  const config = tenants.find(tenant => tenant.tenantOrigin === req.headers.get("origin"));
  if (!config) return Response.json({ error: "forbidden" }, { status: 403 });
  return handleMcpExchange(req, { admin, makeAnon, config });
});

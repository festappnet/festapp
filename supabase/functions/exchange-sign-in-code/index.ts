import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { exchangeSignInCode } from "./exchange.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const options = {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
  global: {
    fetch: ((input, init) =>
      fetch(input, {
        ...init,
        signal: AbortSignal.timeout(8000),
      })) as typeof fetch,
  },
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") {
    return new Response("{}", { status: 405, headers });
  }
  try {
    const raw = await req.text();
    if (raw.length > 1024) return new Response("{}", { status: 400, headers });
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      options,
    );
    const anon = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      options,
    );
    const result = await exchangeSignInCode(JSON.parse(raw), admin, anon);
    // Invalid proofs have one uniform response, with no account-existence signal.
    return new Response(JSON.stringify(result ?? {}), { headers });
  } catch {
    return new Response(
      JSON.stringify({ error: "auth_temporarily_unavailable" }),
      { status: 503, headers },
    );
  }
});

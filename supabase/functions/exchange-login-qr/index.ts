import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { exchangeLoginCredential } from "./exchange.ts";
import { sha256Hex } from "./qr.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const attempts = new Map<string, { minute: number; count: number }>();
const authOptions = {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  global: { fetch: ((input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) })) as typeof fetch },
};
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  authOptions,
);
const makeAnon = () => createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
  authOptions,
);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "invalid_credential" }), {
      status: 405,
      headers: cors,
    });
  }
  if (Number(req.headers.get("content-length") ?? 0) > 1024) {
    return new Response(JSON.stringify({ error: "invalid_credential" }), {
      status: 401,
      headers: cors,
    });
  }
  const source = await sha256Hex(
    `${Deno.env.get("QR_RATE_SALT") ?? "local"}:${
      req.headers.get("x-forwarded-for") ?? "unknown"
    }`,
  );
  const minute = Math.floor(Date.now() / 60000),
    previous = attempts.get(source);
  const count = previous?.minute === minute ? previous.count + 1 : 1;
  attempts.set(source, { minute, count });
  if (count > 30) {
    return new Response(JSON.stringify({ error: "invalid_credential" }), {
      status: 429,
      headers: cors,
    });
  }
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_credential" }), {
      status: 401,
      headers: cors,
    });
  }
  const session = await exchangeLoginCredential(body, admin, makeAnon());
  return session
    ? new Response(JSON.stringify(session), { status: 200, headers: cors })
    : new Response(JSON.stringify({ error: "invalid_credential" }), {
      status: 401,
      headers: cors,
    });
});

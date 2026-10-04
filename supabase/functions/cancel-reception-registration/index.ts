import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { cancelRegistration } from "./cancel.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "registration_unavailable" }), {
      status: 405,
      headers,
    });
  }
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return new Response(JSON.stringify({ error: "registration_unavailable" }), {
      status: 401,
      headers,
    });
  }
  let body: { occasion?: number; user?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "registration_unavailable" }), {
      status: 400,
      headers,
    });
  }
  if (!Number.isSafeInteger(body.occasion) || typeof body.user !== "string") {
    return new Response(JSON.stringify({ error: "registration_unavailable" }), {
      status: 400,
      headers,
    });
  }
  const url = Deno.env.get("SUPABASE_URL")!,
    anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const result = await cancelRegistration(
    body.occasion!,
    body.user,
    createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    }),
    createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
    }),
    createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
    }),
    async (accessToken) => {
      const { error } = await createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
        .auth.admin.signOut(accessToken, "global");
      if (error) throw error;
    },
  );
  return new Response(JSON.stringify(result.body), {
    status: result.status,
    headers,
  });
});

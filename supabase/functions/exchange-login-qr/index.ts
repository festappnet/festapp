import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { exchangeLoginCredential } from "./exchange.ts";
import { handleQrExchange } from "./handler.ts";

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

Deno.serve((req) => handleQrExchange(req, {
  admit: async (occasion) => {
    const { data, error } = await admin.rpc("consume_qr_login_attempt_v1", { p_occasion: occasion });
    if (error) throw new Error("qr_admission_unavailable");
    return data;
  },
  exchange: (body) => exchangeLoginCredential(body, admin, makeAnon()),
}));

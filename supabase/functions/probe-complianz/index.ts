import { handleProbe } from "./handler.ts";
Deno.serve((request) =>
  handleProbe(request, {
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  })
);

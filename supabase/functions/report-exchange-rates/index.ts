import {createRateHandler} from "./handler.ts";
Deno.serve(createRateHandler({authorize: async authorization => {
  const response = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
    headers: {Authorization: authorization, apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? ""},
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) return false;
  const user = await response.json();
  return typeof user.id === "string" && user.id.length > 0;
}}));

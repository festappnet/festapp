import { handleFetchHttpData } from "./handler.ts";

Deno.serve((request: Request) => handleFetchHttpData(request, {
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
}));

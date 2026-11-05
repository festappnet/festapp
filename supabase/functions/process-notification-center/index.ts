import { authorizeRequest } from "../_shared/auth.ts";
import {
  notificationHandler,
  notificationRpc,
} from "../_shared/notificationDispatcher.ts";
const runtime = (globalThis as typeof globalThis & {
  EdgeRuntime?: { waitUntil(work: Promise<unknown>): void };
}).EdgeRuntime;
Deno.serve(notificationHandler({
  authorize: (requestSecret) => authorizeRequest({ requestSecret }),
  rpc: notificationRpc(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  ),
  waitUntil: runtime ? (work) => runtime.waitUntil(work) : undefined,
}));

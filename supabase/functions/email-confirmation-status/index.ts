import { emailRpc } from "../_shared/emailQueueClient.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Cache-Control": "no-store",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") {
    return new Response(null, { status: 405, headers });
  }
  try {
    const { capability } = await req.json();
    if (typeof capability !== "string" || !/^[a-f0-9]{64}$/.test(capability)) {
      return Response.json({ state: "unavailable" }, { status: 403, headers });
    }
    const hash = Array.from(
      new Uint8Array(
        await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(capability),
        ),
      ),
      (b) => b.toString(16).padStart(2, "0"),
    ).join("");
    const state = await emailRpc("get_email_confirmation_status", {
      p_hash: hash,
    });
    return Response.json({ state }, {
      headers,
      status: state === "unavailable" ? 403 : 200,
    });
  } catch {
    return Response.json({ state: "unavailable" }, { status: 503, headers });
  }
});

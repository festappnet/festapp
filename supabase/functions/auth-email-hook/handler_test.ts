import { assert, assertEquals } from "jsr:@std/assert@1";
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { authEmailHandler } from "./handler.ts";
const secret = btoa("fixture-auth-hook-key-only-123456");
const payload = {
  user: {
    id: "00000000-0000-4000-8000-000000000001",
    email: "fixture@example.invalid",
  },
  email_data: {
    email_action_type: "recovery",
    token: "123456",
    token_hash: "private-proof",
    redirect_to: "https://app.example.invalid",
    site_url: "https://api.example.invalid",
  },
};
function request(tampered = false) {
  const body = JSON.stringify(payload),
    id = "fixture-hook-id",
    timestamp = new Date();
  const signature = new Webhook(secret).sign(id, timestamp, body);
  return new Request("https://api.example.invalid", {
    method: "POST",
    body: tampered ? body + " " : body,
    headers: {
      "webhook-id": id,
      "webhook-timestamp": String(Math.floor(timestamp.getTime() / 1000)),
      "webhook-signature": signature,
    },
  });
}
Deno.test("signed Auth hook only acknowledges a durable encrypted intent and replays stable identity", async () => {
  let available = false;
  const intents = new Set<string>();
  const handler = authEmailHandler({
    secret: `v1,whsec_${secret}`,
    publicAuthUrl: "https://api.example.invalid",
    prepare: async () => ({
      p_sealed: { v: "1", iv: "fixture", ciphertext: "encrypted" },
      p_content_hash: "rendered",
    }),
    rpc: async (name, args) => {
      if (name === "get_auth_email_context") {
        return { organization: 1, recipient: "fixture@example.invalid" };
      }
      if (!available) throw new Error("DB down");
      assert(!JSON.stringify(args).includes("private-proof"));
      assert(!JSON.stringify(args).includes("123456"));
      intents.add(String(args.p_dedupe));
    },
  });
  assertEquals((await handler(request())).status, 503);
  assertEquals(intents.size, 0);
  available = true;
  assertEquals((await handler(request())).status, 200);
  assertEquals((await handler(request())).status, 200);
  assertEquals(intents.size, 1);
  assertEquals((await handler(request(true))).status, 503);
  assertEquals(intents.size, 1);
});

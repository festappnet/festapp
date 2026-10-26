import { assertEquals, assertExists } from "jsr:@std/assert@1";
type EdgeHandler = (request: Request) => Response | Promise<Response>;
const testEnvironment = {
  SUPABASE_URL: "https://invitation-fixture.invalid",
  SUPABASE_ANON_KEY: "fixture-anon",
  SUPABASE_SERVICE_ROLE_KEY: "fixture-service-role",
  DEFAULT_EMAIL: "sender@example.invalid",
};
async function loadHandler(): Promise<EdgeHandler> {
  const originalServe = Deno.serve;
  let captured: EdgeHandler | undefined;
  Deno.serve = ((handler: EdgeHandler) => {
    captured = handler;
    return {} as Deno.HttpServer;
  }) as typeof Deno.serve;
  try {
    await import("../send-sign-in-code/index.ts");
  } finally {
    Deno.serve = originalServe;
  }
  assertExists(captured);
  return captured;
}

Deno.test("invitation preserves a queued intent during provider outage and confirms only accepted mail", async () => {
  const originalFetch = globalThis.fetch;
  const previousEnv = Object.fromEntries(
    Object.keys(testEnvironment).map((key) => [key, Deno.env.get(key)]),
  );
  for (const [key, value] of Object.entries(testEnvironment)) {
    Deno.env.set(key, value);
  }
  const originalKey = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set(
    "EMAIL_PAYLOAD_KEY",
    btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
  );
  let state = "retry_wait";
  const queuedIntents: string[] = [];
  const messageId = "00000000-0000-4000-8000-000000000001";
  globalThis.fetch = async (url, options) => {
    const path = new URL(String(url)).pathname;
    if (path.endsWith("/get_sign_in_recipient_context_v1")) {
      return Response.json({ capabilities: {} });
    }
    if (path.endsWith("/occasions")) return Response.json({ organization: 1 });
    if (path.endsWith("/organizations")) {
      return Response.json({
        data: { APP_NAME: "Fixture", DEFAULT_LANGUAGE: "cs" },
      });
    }
    if (path.endsWith("/user_info")) {
      return Response.json({
        email_readonly: "fixture@example.invalid",
        name: "Anna",
        surname: "Fixture",
      });
    }
    if (path.endsWith("/get_user_delivery_email")) {
      return Response.json("fixture@example.invalid");
    }
    if (path.endsWith("/admit_email_preparation_v1")) {
      return Response.json(true);
    }
    if (path.endsWith("/get_email_template_and_wrapper")) {
      return Response.json({
        template: { subject: "Invitation", html: "Code: {{code}}" },
      });
    }
    if (path.endsWith("/reset_password_and_enqueue_email")) {
      const args = JSON.parse(String(options!.body));
      queuedIntents.push(args.p_dedupe);
      return Response.json({
        message_id: messageId,
        replayed: queuedIntents.length > 1,
      });
    }
    if (path.endsWith("/get_internal_email_state")) return Response.json(state);
    throw Error("Unexpected invitation transport: " + path);
  };
  const handler = await loadHandler();
  const request = () =>
    new Request("https://edge-test.invalid", {
      method: "POST",
      headers: {
        authorization: "Bearer fixture",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        usr: "00000000-0000-4000-8000-000000000002",
        oc: 1,
        requestId: "same-intent",
      }),
    });
  try {
    const pending = await handler(request());
    assertEquals(pending.status, 202);
    assertEquals((await pending.json()).status, "queued");
    state = "accepted";
    const sent = await handler(request());
    assertEquals(sent.status, 200);
    assertEquals((await sent.json()).status, "sent");
    assertEquals(queuedIntents.length, 2);
    assertEquals(
      queuedIntents[0],
      queuedIntents[1],
      "checking queued delivery retains the request identity",
    );
    state = "dead";
    const failed = await handler(request());
    assertEquals(failed.status, 500);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of Object.entries(previousEnv)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
    if (originalKey === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
    else Deno.env.set("EMAIL_PAYLOAD_KEY", originalKey);
  }
});

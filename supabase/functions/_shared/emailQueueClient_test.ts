import { assertEquals, assertRejects } from "jsr:@std/assert@1";

Deno.test("a custom request ID cannot replay different rendered content", async () => {
  const originalFetch = globalThis.fetch;
  const originalUrl = Deno.env.get("SUPABASE_URL"),
    originalKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    originalPayload = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set("SUPABASE_URL", "https://canonical-fixture.invalid");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "isolated-fixture");
  Deno.env.set(
    "EMAIL_PAYLOAD_KEY",
    btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
  );
  const hashes = new Map<string, string>();
  let inserts = 0;
  globalThis.fetch = async (url, options) => {
    const path = new URL(String(url)).pathname;
    if (path.endsWith("/get_email_template_and_wrapper")) {
      return Response.json({});
    }
    if (path.endsWith("/enqueue_prepared_email")) {
      const args = JSON.parse(String(options!.body));
      assertEquals(args.p_dedupe, "explicit-request");
      const previous = hashes.get(args.p_dedupe);
      if (previous && previous !== args.p_content_hash) {
        return Response.json({
          code: "P0001",
          message: "email_dedupe_conflict",
        }, { status: 409 });
      }
      if (!previous) {
        hashes.set(args.p_dedupe, args.p_content_hash);
        inserts++;
      }
      return Response.json({
        message_id: "fixture-message",
        state: "accepted",
      });
    }
    if (path.endsWith("/get_internal_email_state")) {
      return Response.json("accepted");
    }
    throw Error("Unexpected fixture transport: " + path);
  };
  try {
    const { enqueueAndAwaitEmail } = await import("./emailQueueClient.ts");
    const input = {
      to: "fixture@example.invalid",
      from: "sender@example.invalid",
      replyTo: "sender@example.invalid",
      context: { organization: 1 },
      templateCode: "CUSTOM",
      template: { id: 1, subject: "Original", html: "<p>Original</p>" },
      substitutions: {},
      kind: "custom" as const,
      dedupeKey: "explicit-request",
    };
    await enqueueAndAwaitEmail(input);
    await enqueueAndAwaitEmail(input);
    assertEquals(inserts, 1, "identical retries join one intent");
    await assertRejects(
      () =>
        enqueueAndAwaitEmail({
          ...input,
          template: { ...input.template, subject: "Changed" },
        }),
      Error,
      "email_rpc_enqueue_prepared_email",
    );
    await assertRejects(
      () =>
        enqueueAndAwaitEmail({
          ...input,
          template: { ...input.template, html: "<p>Changed</p>" },
        }),
      Error,
      "email_rpc_enqueue_prepared_email",
    );
    assertEquals(inserts, 1, "changed content does not create a successor");
  } finally {
    globalThis.fetch = originalFetch;
    for (
      const [name, value] of [["SUPABASE_URL", originalUrl], [
        "SUPABASE_SERVICE_ROLE_KEY",
        originalKey,
      ], ["EMAIL_PAYLOAD_KEY", originalPayload]]
    ) {
      if (value === undefined) Deno.env.delete(name!);
      else Deno.env.set(name!, value);
    }
  }
});

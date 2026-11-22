import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.env.set("SUPABASE_URL", "https://email-test.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only");
const { renderQueuedEmail } = await import("./emailRenderer.ts");

const base = {
  message_id: "notice", message_kind: "custom", code: "ACCOUNT_MFA_METHOD_ADDED",
  recipient: "delivery@example.invalid", organization: 3, unit: 0, occasion: 0,
  order_id: 0, lease_token: "lease", attempt_id: "attempt", prepared: null,
};

Deno.test("enrollment email identifies the sign-in account independently of delivery address", async () => {
  const { prepared, postAction } = await renderQueuedEmail({
    ...base, data: {
      lang: "cs", account_email: "jana&team@example.invalid", method: "passkey",
      origin: "https://vstupenky.online",
    },
  });
  assertEquals(prepared.to, base.recipient);
  assertEquals(prepared.subject, "K účtu byla přidána passkey · vstupenky.online");
  assertStringIncludes(prepared.html, "<strong>Účet:</strong> jana&amp;team@example.invalid");
  assertStringIncludes(prepared.html, "<strong>Platforma:</strong> vstupenky.online");
  assertStringIncludes(prepared.html, "<strong>Metoda:</strong> Passkey");
  assertEquals(postAction.tracking_policy, "disabled");
});

Deno.test("enrollment email localizes authenticator type and tolerates previously queued notices", async () => {
  const { prepared } = await renderQueuedEmail({
    ...base, data: { lang: "en", method: "totp", origin: "javascript:alert(1)" },
  });
  assertStringIncludes(prepared.html, "<strong>Method:</strong> Authenticator app");
  assertEquals(prepared.html.includes("javascript:"), false);
  const legacy = await renderQueuedEmail({ ...base, data: { lang: "cs" } });
  assertEquals(legacy.prepared.subject, "Byl přidán způsob ověření");
  assertEquals(legacy.prepared.html.includes(base.recipient), false);
});

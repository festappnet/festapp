import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { monitorEdgeRequest } from "./monitoring.ts";
import { firstLoginEmail } from "./firstLoginEmail.ts";

Deno.test("router preserves responses and exceptions while reporting only safe failure facts", async () => {
  const original = globalThis.fetch;
  const batches: any[] = [];
  globalThis.fetch = ((_url: unknown, init: RequestInit) => {
    const body = JSON.parse(String(init.body)); batches.push(body);
    return Promise.resolve(Response.json({ results: body.events.map((e: any) => ({ eventId: e.event_id, recorded: true })) }, { status: 202 }));
  }) as typeof fetch;
  const environment = { FESTAPP_MONITORING_TOKEN: "fixture-monitoring-token-123456789012345", FESTAPP_MONITORING_URL: "https://monitoring.example.invalid" };
  const request = new Request("https://app.example.invalid/?password=private", { method: "POST", body: "private@example.invalid" });
  try {
    const healthy = new Response("ok");
    assertEquals(await monitorEdgeRequest("register", request, () => Promise.resolve(healthy), environment), healthy);
    assertEquals(batches.length, 0);
    const failed = new Response("sensitive body", { status: 503 });
    assertEquals(await monitorEdgeRequest("register", request, () => Promise.resolve(failed), environment), failed);
    await assertRejects(() => monitorEdgeRequest("register", request, () => { throw new Error("private@example.invalid"); }, environment), Error, "private@example.invalid");
    assertEquals(batches.length, 2);
    assertEquals(batches[0].events[0].context, { http_status: 503 });
    assertEquals(JSON.stringify(batches).includes("private"), false);
  } finally { globalThis.fetch = original; }
});

Deno.test("Monitoring rejection cannot turn an application response into another failure", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("", { status: 403 }))) as typeof fetch;
  try {
    const response = new Response("original", { status: 500 });
    assertEquals(await monitorEdgeRequest("register", new Request("https://test.invalid"), () => Promise.resolve(response), {
      FESTAPP_MONITORING_TOKEN: "fixture-monitoring-token-123456789012345", FESTAPP_MONITORING_URL: "https://monitoring.example.invalid",
    }), response);
  } finally { globalThis.fetch = original; }
});

Deno.test("first login owner mail escapes user input and contains no sign-in secret", () => {
  const mail = firstLoginEmail("owner@example.invalid", { name: '<script>alert("x")</script>', email: "new@example.invalid", app_name: "Tickets", signed_in_at: "2026-10-09T12:00:00Z", password: "secret" }, "sender@example.invalid");
  assertEquals(mail.to, "owner@example.invalid");
  assertEquals(mail.html.includes("<script>"), false);
  assertEquals(mail.html.includes("new@example.invalid"), true);
  assertEquals(JSON.stringify(mail).includes("secret"), false);
});

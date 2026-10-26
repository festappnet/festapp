import { assertEquals } from "jsr:@std/assert@1";
import { handleQrExchange, type QrDependencies } from "./handler.ts";
const request = (body: BodyInit, headers = {}) => new Request("https://fixture.invalid", { method: "POST", body, headers });
const code = JSON.stringify({ occasion: 42, manualCode: "ABCDEFGH" });
Deno.test("QR exchange uses durable global and event gates before verification", async () => {
  const calls: Array<number | null> = [];
  let exchanged = 0;
  const deps: QrDependencies = {
    admit: async (id) => { calls.push(id); return { allowed: true, maxBodyBytes: 1024 }; },
    exchange: async () => { exchanged++; return { access_token: "fixture" }; },
  };
  assertEquals((await handleQrExchange(request(code, { "x-forwarded-for": "forged" }), deps)).status, 200);
  assertEquals(calls, [null, 42]);
  assertEquals(exchanged, 1);
});
Deno.test("QR outage and exhausted gates stop session work across handler instances", async () => {
  let attempts = 0, exchanged = 0;
  const deps: QrDependencies = {
    admit: async () => ({ allowed: ++attempts <= 1, maxBodyBytes: 1024 }),
    exchange: async () => { exchanged++; return {}; },
  };
  assertEquals((await handleQrExchange(request(code), deps)).status, 429);
  assertEquals((await handleQrExchange(request(code), { ...deps })).status, 429);
  assertEquals(exchanged, 0);
  assertEquals((await handleQrExchange(request(code), { ...deps, admit: () => Promise.reject(new Error("offline")) })).status, 503);
});
Deno.test("QR counts actual stream bytes without Content-Length", async () => {
  let exchanged = false;
  const body = new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode("x".repeat(1025))); c.close(); } });
  const deps: QrDependencies = { admit: async () => ({ allowed: true, maxBodyBytes: 1024 }), exchange: async () => { exchanged = true; return {}; } };
  assertEquals((await handleQrExchange(request(body), deps)).status, 413);
  assertEquals(exchanged, false);
});

import { assertEquals } from "jsr:@std/assert";
import { handleFetchHttpData } from "./handler.ts";

const targetUrl = "https://images.example/photo.png";
const backend = "https://backend.example";

function request(body: unknown, token: string | null = "editor"): Request {
  return new Request("https://function.example", {
    method: "POST",
    headers: token === null ? {} : { Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

// The role decision is the existing SQL RPC's responsibility. These tests
// verify that the endpoint uses its result and the caller JWT without bypass.
function transport(permission: boolean | number = true) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const dependencies = {
    supabaseUrl: backend,
    anonKey: "public-api-key",
    resolveDns: () => Promise.resolve(["203.0.113.1"]),
    fetch: (input: RequestInfo | URL, init?: RequestInit) => {
      const url = input.toString();
      calls.push({ url, init: init ?? {} });
      if (url.startsWith(backend)) {
        return Promise.resolve(new Response(JSON.stringify(
          typeof permission === "boolean" ? permission : { error: "rejected" },
        ), { status: typeof permission === "number" ? permission : 200 }));
      }
      return Promise.resolve(new Response(new Uint8Array([1, 2, 3]), {
        headers: { "Content-Type": "image/png" },
      }));
    },
  };
  return { calls, dependencies };
}

for (const [role, scope, args] of [
  ["occasion-editor", { occasionId: 4 }, { p_occasion_id: 4 }],
  ["order-editor", { occasionId: 4 }, { p_occasion_id: 4 }],
  ["unit-editor", { unitId: 7 }, { p_unit_id: 7 }],
] as const) {
  Deno.test(`${role}: caller-scoped upload permission precedes external fetch`, async () => {
    const { calls, dependencies } = transport();
    const response = await handleFetchHttpData(request({ targetUrl, ...scope }, role), dependencies);
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { data: "AQID", contentType: "image/png" });
    assertEquals(calls.length, 2);
    assertEquals(calls[0].url, `${backend}/rest/v1/rpc/check_upload_permission`);
    assertEquals(JSON.parse(String(calls[0].init.body)), args);
    const headers = new Headers(calls[0].init.headers);
    assertEquals(headers.get("Authorization"), `Bearer ${role}`);
    assertEquals(headers.get("apikey"), "public-api-key");
    assertEquals(new Headers(calls[1].init.headers).has("Authorization"), false);
    assertEquals(response.headers.get("cache-control"), "no-store");
  });
}

Deno.test("reject both/neither scopes and invalid owner IDs before authorization", async () => {
  for (const scope of [
    {}, { occasionId: 1, unitId: 2 }, { occasionId: 1, unitId: null },
    { occasionId: null }, { unitId: 0 }, { occasionId: -1 },
    { unitId: 1.5 }, { occasionId: "1" }, { unitId: Number.MAX_SAFE_INTEGER + 1 },
  ]) {
    const { calls, dependencies } = transport();
    const response = await handleFetchHttpData(request({ targetUrl, ...scope }), dependencies);
    assertEquals(response.status, 400);
    assertEquals(calls.length, 0);
  }
});

Deno.test("malformed body, method and preflight do not contact the backend", async () => {
  const { calls, dependencies } = transport();
  for (const body of [null, [], "value"]) {
    assertEquals((await handleFetchHttpData(request(body), dependencies)).status, 400);
  }
  assertEquals((await handleFetchHttpData(new Request("https://function.example", {
    method: "POST", body: "{broken",
  }), dependencies)).status, 400);
  assertEquals((await handleFetchHttpData(new Request("https://function.example"), dependencies)).status, 405);
  const preflight = await handleFetchHttpData(new Request("https://function.example", {
    method: "OPTIONS",
  }), dependencies);
  assertEquals(preflight.status, 200);
  assertEquals(preflight.headers.get("access-control-allow-origin"), "*");
  assertEquals(calls.length, 0);
});

Deno.test("missing token and request secret cannot authorize fetch", async () => {
  const { calls, dependencies } = transport();
  const response = await handleFetchHttpData(request({
    targetUrl, occasionId: 4, requestSecret: "system-secret",
  }, null), dependencies);
  assertEquals(response.status, 401);
  assertEquals(calls.length, 0);
});

for (const [token, scope, result, status] of [
  ["expired", { occasionId: 4 }, 401, 401],
  ["group-admin", { occasionId: 4 }, false, 403],
  ["other-occasion", { occasionId: 4 }, false, 403],
  ["other-unit", { unitId: 7 }, false, 403],
  ["service-role-without-user", { occasionId: 4 }, false, 403],
  ["rpc-failure", { occasionId: 4 }, 500, 500],
] as const) {
  Deno.test(`${token}: permission rejection never fetches the external URL`, async () => {
    const { calls, dependencies } = transport(result);
    assertEquals((await handleFetchHttpData(request({ targetUrl, ...scope }, token), dependencies)).status, status);
    assertEquals(calls.length, 1);
  });
}

Deno.test("private target and public hostname resolving privately are rejected", async () => {
  const first = transport();
  assertEquals((await handleFetchHttpData(request({
    targetUrl: "https://127.0.0.1/secret", occasionId: 4,
  }), first.dependencies)).status, 400);
  assertEquals(first.calls.length, 1);
  const second = transport();
  second.dependencies.resolveDns = () => Promise.resolve(["10.0.0.1"]);
  assertEquals((await handleFetchHttpData(request({ targetUrl, unitId: 7 }), second.dependencies)).status, 400);
  assertEquals(second.calls.length, 1);
});

Deno.test("malformed successful RPC response fails closed", async () => {
  const { calls, dependencies } = transport();
  const send = dependencies.fetch;
  dependencies.fetch = (input, init) => input.toString().startsWith(backend)
    ? Promise.resolve(new Response('"true"')) : send(input, init);
  assertEquals((await handleFetchHttpData(request({ targetUrl, occasionId: 4 }), dependencies)).status, 403);
  assertEquals(calls.length, 0);
});

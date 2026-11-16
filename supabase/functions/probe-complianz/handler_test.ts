import { assertEquals } from "jsr:@std/assert";
import { handleProbe } from "./handler.ts";
const origin = "https://organizer.example";
function fixture(overrides: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const deps = {
    supabaseUrl: "https://backend.example",
    anonKey: "anon",
    fetch: (input: string | URL | Request, init?: RequestInit) => {
      const name = String(input).split("/").pop()!;
      calls.push(name);
      assertEquals(
        new Headers(init?.headers).get("Authorization"),
        "Bearer user",
      );
      return Promise.resolve(
        new Response(JSON.stringify(
          name === "get_unit_measurement_approval"
            ? {
              approved: true,
              saved_origins: [origin],
              approved_origins: [origin],
              ...overrides,
            }
            : name === "save_unit_website_consent_binding"
            ? JSON.parse(init!.body as string)
            : {},
        )),
      );
    },
    resolveDns: () => Promise.resolve(["93.184.215.14"]),
    websiteFetch: (url: URL, init: RequestInit, address: string) => {
      calls.push(url.href);
      assertEquals(address, "93.184.215.14");
      assertEquals(init.headers, undefined);
      assertEquals(init.redirect, "manual");
      return Promise.resolve(
        new Response(
          '<script>var complianz={"prefix":"cmplz_rt_","current_policy_id":"42"};</script>',
          { headers: { "Content-Type": "text/html" } },
        ),
      );
    },
  };
  const request = (body: object = {}, auth = true) =>
    new Request("https://backend.example/functions/v1/probe-complianz", {
      method: "POST",
      headers: auth ? { Authorization: "Bearer user" } : {},
      body: JSON.stringify({ unitId: 2, origin, ...body }),
    });
  return { deps, calls, request };
}
Deno.test("authorized saved approved origin detects; confirmation pins fresh server value", async () => {
  const f = fixture();
  const response = await handleProbe(f.request(), f.deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { policyId: "42" });
  const saved = await handleProbe(
    f.request({
      confirm: true,
      expectedPolicyId: "42",
      platform: "wordpress",
      version: 0,
      revision: "a".repeat(32),
    }),
    f.deps,
  );
  assertEquals(saved.status, 200);
  assertEquals((await saved.json()).p_provider_config, {
    provider: "complianz",
    policyId: "42",
  });
  f.calls.length = 0;
  assertEquals(
    (await handleProbe(
      f.request({ confirm: true, expectedPolicyId: "41" }),
      f.deps,
    )).status,
    409,
  );
  assertEquals(f.calls.includes("save_unit_website_consent_binding"), false);
});
Deno.test("missing auth, manager denial, unsaved and unapproved origins never fetch website", async () => {
  for (
    const scope of [{ saved_origins: [] }, { approved_origins: [] }, {
      approved: false,
    }]
  ) {
    const f = fixture(scope);
    assertEquals((await handleProbe(f.request(), f.deps)).status, 403);
    assertEquals(f.calls.length, 2);
  }
  const f = fixture();
  assertEquals((await handleProbe(f.request({}, false), f.deps)).status, 401);
  assertEquals(f.calls.length, 0);
  f.deps.fetch = () => Promise.resolve(new Response("", { status: 403 }));
  assertEquals((await handleProbe(f.request(), f.deps)).status, 403);
});
Deno.test("shared SSRF policy rejects unsafe targets, private DNS and off-origin redirect", async () => {
  const f = fixture();
  for (
    const origin of [
      "http://organizer.example",
      "https://127.0.0.1",
      "https://organizer.example/path",
    ]
  ) {
    assertEquals(
      (await handleProbe(f.request({ origin }), f.deps)).status,
      400,
    );
  }
  f.deps.resolveDns = () => Promise.resolve(["127.0.0.1"]);
  assertEquals((await handleProbe(f.request(), f.deps)).status, 502);
  f.deps.resolveDns = () => Promise.resolve(["93.184.215.14"]);
  f.deps.websiteFetch = () =>
    Promise.resolve(
      new Response(null, {
        status: 302,
        headers: { location: "https://other.example/" },
      }),
    );
  assertEquals((await handleProbe(f.request(), f.deps)).status, 502);
});
Deno.test("blocked, missing, timeout and oversized HTML return detection failure", async () => {
  for (
    const response of [
      new Response("", { status: 403 }),
      new Response("<html></html>", {
        headers: { "content-type": "text/html" },
      }),
      new Response("x".repeat(1024 * 1024 + 1), {
        headers: { "content-type": "text/html" },
      }),
    ]
  ) {
    const f = fixture();
    f.deps.websiteFetch = () => Promise.resolve(response);
    const result = await handleProbe(f.request(), f.deps);
    assertEquals([422, 502].includes(result.status), true);
  }
  const f = fixture();
  f.deps.websiteFetch = () =>
    Promise.reject(new DOMException("timeout", "TimeoutError"));
  assertEquals((await handleProbe(f.request(), f.deps)).status, 502);
});
Deno.test("deployed entrypoint registers handler and serves preflight without credentials", async () => {
  const serve = Deno.serve;
  let handler: ((request: Request) => Promise<Response>) | undefined;
  try {
    Deno.serve = ((callback: typeof handler) => {
      handler = callback;
      return {};
    }) as unknown as typeof Deno.serve;
    await import("./index.ts");
    const response = await handler!(
      new Request("https://backend.example/functions/v1/probe-complianz", {
        method: "OPTIONS",
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  } finally {
    Deno.serve = serve;
  }
});

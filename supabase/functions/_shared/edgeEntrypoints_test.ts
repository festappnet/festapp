import { assertEquals, assertExists } from "jsr:@std/assert@1";

type EdgeHandler = (request: Request) => Response | Promise<Response>;

const testEnvironment = {
  SUPABASE_URL: "https://edge-test.invalid",
  SUPABASE_ANON_KEY: "edge-test-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "edge-test-service-role-key",
  DEFAULT_EMAIL: "noreply@example.invalid",
  PROJECT_URL: "https://edge-test.invalid",
  FESTAPP_ALLOWED_WEB_ORIGINS: "https://app.example.invalid",
  NOTIFY_WEBHOOK_TOKEN: "edge-test-webhook-token",
};

const handlers = new Map<string, EdgeHandler>();

async function loadHandler(name: string): Promise<EdgeHandler> {
  const cached = handlers.get(name);
  if (cached) return cached;
  const originalServe = Deno.serve;
  const previousEnvironment = Object.fromEntries(
    Object.keys(testEnvironment).map((key) => [key, Deno.env.get(key)]),
  );
  let captured: EdgeHandler | undefined;
  Deno.serve = ((first: unknown, second?: unknown) => {
    captured = (typeof first === "function" ? first : second) as EdgeHandler;
    return {
      addr: { transport: "tcp", hostname: "127.0.0.1", port: 0 },
      finished: Promise.resolve(),
      shutdown: () => Promise.resolve(),
      ref: () => {},
      unref: () => {},
    } as unknown as Deno.HttpServer;
  }) as typeof Deno.serve;
  try {
    for (const [key, value] of Object.entries(testEnvironment)) {
      Deno.env.set(key, value);
    }
    await import(`../${name}/index.ts?edge-entrypoint-test=${name}`);
  } finally {
    Deno.serve = originalServe;
    for (const [key, value] of Object.entries(previousEnvironment)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
  assertExists(captured, `${name} did not register an HTTP handler`);
  handlers.set(name, captured);
  return captured;
}

const optionEntrypoints = [
  "report-exchange-rates",
  "process-email-queue",
  "email-confirmation-status",
  "preview-ticket-layout",
  "cancel-reception-registration",
  "confirm-account-deletion",
  "download-ticket",
  "exchange-login-qr",
  "fetch-http-data",
  "fetch-transactions",
  "generate-order-agreement",
  "register",
  "request-account-deletion",
  "send-app-links",
  "send-custom-email",
  "send-email",
  "send-reset-password-link",
  "send-sign-in-code",
  "send-ticket-order",
  "send-tickets",
  "synchronize-orders",
];

for (const name of optionEntrypoints) {
  Deno.test(`${name} registers a reachable CORS preflight`, async () => {
    const handler = await loadHandler(name);
    const response = await handler(
      new Request("https://edge-test.invalid", {
        method: "OPTIONS",
        headers: { origin: "https://app.example.invalid" },
      }),
    );
    assertEquals(response.status, 200);
  });
}

Deno.test("notify rejects an unauthenticated public request", async () => {
  const handler = await loadHandler("notify");
  const response = await handler(new Request("https://edge-test.invalid"));
  assertEquals(response.status, 401);
});

Deno.test("download-ticket rejects invalid input before privileged reads", async () => {
  const handler = await loadHandler("download-ticket");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("fetch-transactions rejects a missing occasion before privileged reads", async () => {
  const handler = await loadHandler("fetch-transactions");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("request-account-deletion requires a bearer identity", async () => {
  const handler = await loadHandler("request-account-deletion");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 401);
});

Deno.test("send-custom-email validates its public request before authorization", async () => {
  const handler = await loadHandler("send-custom-email");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("send-reset-password-link rejects malformed JSON without account disclosure", async () => {
  const handler = await loadHandler("send-reset-password-link");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      headers: { origin: "https://app.example.invalid" },
      body: "{",
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { accepted: true });
});

Deno.test("send-sign-in-code rejects invalid identities before changing a password", async () => {
  const handler = await loadHandler("send-sign-in-code");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("send-tickets rejects invalid input before privileged reads", async () => {
  const handler = await loadHandler("send-tickets");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("synchronize-orders rejects a request without system authorization", async () => {
  const handler = await loadHandler("synchronize-orders");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: "{}",
    }),
  );
  assertEquals(response.status, 401);
});

Deno.test("preview rejects missing JWT before privileged work", async () => {
  const response = await (await loadHandler("preview-ticket-layout"))(
    new Request("https://edge-test.invalid", { method: "POST", body: "{}" }),
  );
  assertEquals(response.status, 401);
});

for (
  const name of [
    "google-auth-start",
    "google-auth-callback",
    "google-auth-complete",
  ]
) {
  Deno.test(`${name} registers but stays unavailable without private OAuth inputs`, async () => {
    const handler = await loadHandler(name);
    const response = await handler(
      new Request("https://edge-test.invalid", { method: "POST", body: "{}" }),
    );
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "provider_unavailable" });
    assertEquals(response.headers.get("Cache-Control"), "no-store");
  });
}

for (
  const name of [
    "process-email-queue",
    "email-provider-events",
    "auth-email-hook",
  ]
) {
  Deno.test(`${name} rejects an untrusted request before privileged work`, async () => {
    const handler = await loadHandler(name);
    const response = await handler(
      new Request("https://edge-test.invalid", { method: "POST", body: "{}" }),
    );
    assertEquals(response.status >= 400, true);
  });
}
Deno.test("confirmation status needs an opaque capability, never an order ID", async () => {
  const handler = await loadHandler("email-confirmation-status");
  const response = await handler(
    new Request("https://edge-test.invalid", {
      method: "POST",
      body: JSON.stringify({ orderId: 1 }),
    }),
  );
  assertEquals(response.status, 403);
});

for (const name of ["bank-sync-manage", "bank-sync-reconcile"]) {
  Deno.test(`${name} rejects missing authorization before bank access`, async () => {
    const handler = await loadHandler(name);
    const response = await handler(new Request("https://edge-test.invalid", {method:"POST",body:"{}"}));
    assertEquals(response.status, 401);
  });
}

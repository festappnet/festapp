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
  "delete-order",
  "report-exchange-rates",
  "process-email-queue",
  "email-confirmation-status",
  "preview-ticket-layout",
  "cancel-reception-registration",
  "confirm-account-deletion",
  "download-ticket",
  "exchange-login-qr",
  "exchange-sign-in-code",
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
  "waitlist-commands",
  "customer-order-access",
  "send-tickets",
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

Deno.test("waitlist-commands rejects malformed command before privileged reads", async () => {
  const handler = await loadHandler("waitlist-commands");
  const response = await handler(new Request("https://edge-test.invalid", { method: "POST", body: "{}" }));
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { code: 400, error: "invalid_waitlist_command" });
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.headers.get("Referrer-Policy"), "no-referrer");
});

for (const operation of ["send", "cancel"]) {
  Deno.test(`waitlist-commands requires an editor identity for ${operation}`, async () => {
    const handler = await loadHandler("waitlist-commands");
    const response = await handler(new Request("https://edge-test.invalid", {
      method: "POST", body: JSON.stringify({ operation, payload: {},
        commandId: "cc000000-0000-0000-0000-000000000001", clientId: "cc000000-0000-0000-0000-000000000002" }),
    }));
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { code: 401, error: "unauthorized" });
  });
}

Deno.test("waitlist-commands rejects GET without consuming an offer", async () => {
  const handler = await loadHandler("waitlist-commands");
  const response = await handler(new Request("https://edge-test.invalid", { method: "GET" }));
  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "method_not_allowed" });
});

Deno.test("exchange-sign-in-code rejects GET before privileged work", async () => {
  const response = await (await loadHandler("exchange-sign-in-code"))(new Request("https://edge-test.invalid"));
  assertEquals(response.status, 405);
  assertEquals(await response.json(), {});
  assertEquals(response.headers.get("Cache-Control"), "no-store");
});

Deno.test("exchange-sign-in-code bounds payload before privileged work", async () => {
  const response = await (await loadHandler("exchange-sign-in-code"))(new Request("https://edge-test.invalid", {
    method: "POST", body: "x".repeat(1025),
  }));
  assertEquals(response.status, 400);
  assertEquals(await response.json(), {});
});

Deno.test("exchange-sign-in-code hides invalid proof and account existence", async () => {
  const handler = await loadHandler("exchange-sign-in-code");
  // This entrypoint resolves its clients at request time, after loadHandler has
  // restored process environment. Keep synthetic inputs scoped to this call.
  const keys = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"] as const;
  const previous = keys.map((key) => Deno.env.get(key));
  try {
    keys.forEach((key) => Deno.env.set(key, testEnvironment[key]));
    const response = await handler(new Request("https://edge-test.invalid", { method: "POST", body: "{}" }));
    assertEquals(response.status, 200);
    assertEquals(await response.json(), {});
    assertEquals(response.headers.get("Cache-Control"), "no-store");
  } finally {
    keys.forEach((key, index) => {
      if (previous[index] === undefined) Deno.env.delete(key);
      else Deno.env.set(key, previous[index]!);
    });
  }
});

Deno.test("first ticket delivery joins the paid intent while explicit resend gets a new identity", async () => {
  const handler = await loadHandler("send-tickets");
  const { supabaseAdmin } = await import("./supabaseUtil.ts");
  const originalRpc = supabaseAdmin.rpc;
  const enqueues: Record<string, unknown>[] = [];
  supabaseAdmin.rpc = ((name: string, args: Record<string, unknown>) => {
    let data: unknown;
    if (name === "get_order_details_for_email") {
      data = {
        code: 200,
        data: {
          order: { id: 42, data: { email: "regression@example.invalid" } },
          occasion: { id: 7, organization: 3, unit: 8 },
        },
      };
    } else if (name === "is_demo_occasion") data = false;
    else if (name === "check_request_secret") data = true;
    else if (name === "enqueue_order_email") {
      enqueues.push(args);
      data = { message_id: "fixture-message" };
    } else if (name === "get_internal_email_state") data = "accepted";
    else throw new Error("Unexpected RPC: " + name);
    return Promise.resolve({ data, error: null });
  }) as unknown as typeof supabaseAdmin.rpc;
  try {
    for (const firstDelivery of [true, false]) {
      const response = await handler(
        new Request("https://edge-test.invalid", {
          method: "POST",
          body: JSON.stringify({
            orderId: 42,
            email: "regression@example.invalid",
            requestSecret: "fixture-secret",
            requestId: "fixture-click",
            firstDelivery,
          }),
        }),
      );
      assertEquals(response.status, 200);
    }
    assertEquals(
      enqueues[0].p_request,
      undefined,
      "First delivery must reuse the automatic paid generation",
    );
    assertEquals(
      enqueues[1].p_request,
      "resend:fixture-click:42:regression@example.invalid",
    );
  } finally {
    supabaseAdmin.rpc = originalRpc;
  }
});

Deno.test("customer-order-access rejects unsafe methods and malformed scope without privileged work", async () => {
  const handler = await loadHandler("customer-order-access");
  const get = await handler(new Request("https://edge-test.invalid"));
  assertEquals(get.status, 405);
  const invalid = await handler(new Request("https://edge-test.invalid", {method: "POST", body: "{}"}));
  assertEquals(invalid.status, 403);
  assertEquals(invalid.headers.get("Cache-Control"), "no-store");
  assertEquals(invalid.headers.get("Referrer-Policy"), "no-referrer");
  const reissue = await handler(new Request("https://edge-test.invalid", {method: "POST", body: JSON.stringify({
    commandId: "cc000000-0000-0000-0000-000000000001", reissue: true,
  })}));
  assertEquals(reissue.status, 403);
  const admin = await handler(new Request("https://edge-test.invalid", {method: "POST", body: JSON.stringify({
    commandId: "cc000000-0000-0000-0000-000000000001", admin: true, orderId: 12,
    actor: "11111111-1111-1111-1111-111111111111",
  })}));
  assertEquals(admin.status, 403);
});

Deno.test("customer ticket download rejects foreign tickets before details or PDF work", async () => {
 const handler=await loadHandler("download-ticket");
 const {supabaseAdmin}=await import('./supabaseUtil.ts');
 const previousRpc=supabaseAdmin.rpc,reads:string[]=[];
 try {
  supabaseAdmin.rpc=((name:string)=>{
   reads.push(name);
   if(name!=='get_customer_order_overview')throw new Error('Unexpected privileged read');
   return Promise.resolve({data:{code:200,root:{hasTickets:true},orders:[{state:'sent',tickets:[{id:8,rawState:'sent'}]}]},error:null});
  }) as unknown as typeof supabaseAdmin.rpc;
  const response=await handler(new Request('https://edge-test.invalid',{method:'POST',body:JSON.stringify({ticketId:7,orderId:1,token:'a'.repeat(64)})}));
  assertEquals(response.status,403);assertEquals(response.headers.get('Cache-Control'),'no-store');
  assertEquals(reads,['get_customer_order_overview']);
  const missing=await handler(new Request('https://edge-test.invalid',{method:'POST',body:JSON.stringify({ticketId:7})}));
  assertEquals(missing.status,401);assertEquals(reads.length,1);
 } finally {supabaseAdmin.rpc=previousRpc;}
});

Deno.test("delete-order rejects missing authorization before privileged work", async () => {
  const handler = await loadHandler("delete-order");
  const response = await handler(new Request("https://edge-test.invalid", {
    method: "POST", body: "{}",
  }));
  assertEquals(response.status, 401);
});

Deno.test("delete-order requires explicit invoice opt-in and valid command identity", async () => {
  const handler = await loadHandler("delete-order");
  for (const body of [{}, { orderId: 1, commandId: "invalid", deleteFakturoidInvoice: true },
    { orderId: 1, commandId: "12345678-1234-4234-8234-123456789012", deleteFakturoidInvoice: false }]) {
    const response = await handler(new Request("https://edge-test.invalid", {
      method: "POST", headers: { authorization: "Bearer invalid" }, body: JSON.stringify(body),
    }));
    assertEquals(response.status, 400);
  }
});

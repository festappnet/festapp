import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  sendSes,
  sesBody,
  type SesConfig,
  SesFailure,
  sesRequest,
  verifySesAccount,
} from "./sesProvider.ts";
import { gatewayAttempt } from "../send-email-gateway/gateway.ts";
import { normalizeSesEvents } from "../email-provider-events/events.ts";
import { openEmail, sealEmail } from "./emailPayload.ts";
import { drainEmails } from "./emailDispatcher.ts";
const config: SesConfig = {
  region: "eu-central-1",
  accessKey: "fixture",
  secretKey: "fixture-only",
  sender: "sender@example.invalid",
  securitySet: "security-fixture",
  transactionalSet: "transaction-fixture",
  maxBytes: 30000000,
};
const prepared = {
  from: config.sender,
  to: "recipient@example.invalid",
  subject: "Fixture",
  html: "<p>Fixture</p>",
  replyTo: "reply@example.invalid",
  attachments: Array.from(
    { length: 4 },
    (_, i) => ({
      filename: `ticket-${i}.pdf`,
      content: "AQID",
      contentType: "application/pdf",
      encoding: "base64" as const,
    }),
  ),
};
Deno.test("SES preserves all attachments, Reply-To, config and correlation", () => {
  const body = sesBody(prepared, config, { attempt_id: "fixture" }, false);
  assertEquals(body.Content.Simple.Attachments.length, 4);
  assertEquals(body.ReplyToAddresses, [prepared.replyTo]);
  assertEquals(body.ConfigurationSetName, config.transactionalSet);
  assertEquals(
    sesBody(prepared, config, {}, true).ConfigurationSetName,
    config.securitySet,
  );
});
Deno.test("SES accepted needs MessageId; ambiguous network and response never retry", async () => {
  assertEquals(
    await sendSes(
      prepared,
      config,
      {},
      true,
      (() =>
        Promise.resolve(
          Response.json({ MessageId: "provider-fixture" }),
        )) as typeof fetch,
    ),
    "provider-fixture",
  );
  for (
    const stub of [
      () => Promise.reject(new Error("disconnect")),
      () => Promise.resolve(Response.json({})),
      () => Promise.resolve(new Response("", { status: 500 })),
    ]
  ) {
    const error = await assertRejects(
      () => sendSes(prepared, config, {}, true, stub as typeof fetch),
      SesFailure,
    );
    assertEquals(error.outcome, "unknown");
  }
  const throttle = await assertRejects(
    () =>
      sendSes(
        prepared,
        config,
        {},
        true,
        (() =>
          Promise.resolve(
            Response.json({ __type: "TooManyRequestsException" }, {
              status: 429,
            }),
          )) as typeof fetch,
      ),
    SesFailure,
  );
  assertEquals(throttle.outcome, "retry");
});
Deno.test("gateway replay cannot call provider twice; failed acceptance write never retries SES", async () => {
  let state = "preparing", sent = 0;
  const d = {
    config,
    open: () => Promise.resolve(prepared),
    send: () => {
      sent++;
      return Promise.resolve("provider-id");
    },
    rpc: (name: string) => {
      if (name === "begin_email_send") {
        if (state !== "preparing") {
          return Promise.resolve({
            disposition: "replay",
          });
        }
        state = "sending";
        return Promise.resolve({
          disposition: "send",
          message: {
            prepared: {},
            recipient: prepared.to,
            message_id: "m",
            message_kind: "order_tickets",
            organization: 1,
            tracking_policy: "disabled",
          },
        });
      }
      return Promise.reject(new Error("DB down after acceptance"));
    },
  };
  await assertRejects(() => gatewayAttempt("a", "t", d));
  await gatewayAttempt("a", "t", d);
  assertEquals(sent, 1);
});
Deno.test("SNS normalization strips click URL, tokens, IP and UA", () => {
  const events = normalizeSesEvents(
    {
      eventType: "Click",
      mail: {
        messageId: "ses-id",
        timestamp: "2026-10-03T10:00:00Z",
        destination: ["recipient@example.invalid"],
        tags: { attempt_id: ["00000000-0000-4000-8000-000000000001"] },
      },
      click: {
        timestamp: "2026-10-03T10:01:00Z",
        link: "https://example.invalid?token=secret",
        ipAddress: "1.1.1.1",
        userAgent: "fixture",
      },
    },
    "topic",
    "event",
  );
  assertEquals(events[0].type, "click");
  assert(!JSON.stringify(events).includes("secret"));
  assert(!JSON.stringify(events).includes("1.1.1.1"));
});
Deno.test("prepared payload is encrypted and authenticated", async () => {
  const before = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("a".repeat(32)));
  try {
    const encrypted = await sealEmail({ code: "private-code" });
    assert(!JSON.stringify(encrypted).includes("private-code"));
    assertEquals(await openEmail(encrypted), { code: "private-code" });
    encrypted.ciphertext = encrypted.ciphertext.slice(0, -4) + "AAAA";
    await assertRejects(() => openEmail(encrypted));
  } finally {
    if (before === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
    else Deno.env.set("EMAIL_PAYLOAD_KEY", before);
  }
});
Deno.test("worker reuses immutable preparation; gateway uncertainty does not release for retry", async () => {
  let clock = 0, preparedCount = 0;
  const calls: string[] = [];
  const row = {
    message_id: "m",
    attempt_id: "a",
    lease_token: "t",
    prepared: { sealed: "existing" },
  };
  const result = await drainEmails({
    now: () => clock,
    rpc: (name) => {
      calls.push(name);
      return Promise.resolve(name === "claim_email" ? row : null);
    },
    prepare: () => {
      preparedCount++;
      throw new Error("must reuse");
    },
    seal: () => Promise.resolve({}),
    gateway: () => {
      clock = 40000;
      return Promise.reject(new Error("timeout"));
    },
  });
  assertEquals(result.claimed, 1);
  assertEquals(preparedCount, 0);
  assert(!calls.includes("finish_email_attempt"));
});

Deno.test("gateway verifies actual credential account and signs STS independently", async () => {
  const stub: typeof fetch = async (url, init) => {
    assert(String(url).includes("sts.eu-central-1.amazonaws.com"));
    assert(
      String((init!.headers as Record<string, string>).authorization).includes(
        "/sts/aws4_request",
      ),
    );
    assertEquals(init!.body, "Action=GetCallerIdentity&Version=2011-06-15");
    return new Response(
      "<GetCallerIdentityResponse><Account>123456789012</Account></GetCallerIdentityResponse>",
    );
  };
  assertEquals(
    await verifySesAccount(config, "123456789012", stub),
    "123456789012",
  );
  const mismatch = await assertRejects(
    () => verifySesAccount(config, "999999999999", stub),
    SesFailure,
  );
  assertEquals(mismatch.code, "account_identity_mismatch");
});
Deno.test("click tracking requires explicit public-only allowlist; bearer URLs and auth are excluded", async () => {
  const { safeClickTracking } = await import("./emailTracking.ts");
  assert(
    safeClickTracking(
      '<a href="https://app.example.invalid/privacy">Privacy</a>',
      ["https://app.example.invalid"],
    ),
  );
  for (
    const href of [
      "https://app.example.invalid/?token=secret",
      "https://app.example.invalid/ticket/secret",
      "https://untrusted.example.invalid/",
      "mailto:user@example.invalid",
    ]
  ) {
    assert(
      !safeClickTracking(`<a href="${href}">link</a>`, [
        "https://app.example.invalid",
      ]),
    );
  }
  assert(
    !safeClickTracking("<a href=https://app.example.invalid/>link</a>", [
      "https://app.example.invalid",
    ]),
  );
  const withSet = { ...config, engagementSet: "engagement-fixture" };
  assertEquals(
    sesBody(prepared, withSet, {}, false, true).ConfigurationSetName,
    "engagement-fixture",
  );
  assertEquals(
    sesBody(prepared, withSet, {}, true, true).ConfigurationSetName,
    config.securitySet,
  );
});
Deno.test("SES preflight rejects missing feedback and any sensitive engagement destination", async () => {
  const { verifySesConfiguration } = await import("./sesProvider.ts");
  const topic = "arn:aws:sns:eu-central-1:123456789012:fixture";
  let unsafe = false, missing = false;
  const stub: typeof fetch = async (url) => {
    const target = String(url);
    if (target.includes("/identities/")) {
      return Response.json({ VerifiedForSendingStatus: true });
    }
    const sensitive = target.includes("/security-fixture/");
    return Response.json({
      EventDestinations: [{
        Enabled: true,
        SnsDestination: { TopicArn: missing ? "other-topic" : topic },
        MatchingEventTypes: [
          "SEND",
          "DELIVERY",
          "BOUNCE",
          "COMPLAINT",
          "REJECT",
          "RENDERING_FAILURE",
          "DELIVERY_DELAY",
          ...(!sensitive || unsafe ? ["OPEN"] : []),
        ],
      }],
    });
  };
  await verifySesConfiguration(config, topic, stub);
  unsafe = true;
  assertEquals(
    (await assertRejects(
      () => verifySesConfiguration(config, topic, stub),
      SesFailure,
    )).code,
    "unsafe_tracking_configuration",
  );
  unsafe = false;
  missing = true;
  assertEquals(
    (await assertRejects(
      () => verifySesConfiguration(config, topic, stub),
      SesFailure,
    )).code,
    "feedback_destination_missing",
  );
});
Deno.test("blocked preparation or stale quota does not create an empty continuation wake loop", async () => {
  const calls: string[] = [];
  await drainEmails({
    now: () => 1000,
    rpc: async (name) => {
      calls.push(name);
      return null;
    },
    prepare: async () => {
      throw new Error("unreachable");
    },
    seal: async () => ({}),
    gateway: async () => {},
  });
  assert(!calls.includes("wake_email_worker"));
});

Deno.test("gateway rejects corrupt or mismatched frozen payload before provider call", async () => {
  for (const corrupt of [false, true]) {
    let sent = 0;
    const finishes: any[] = [];
    const result = await gatewayAttempt("a", "t", {
      config,
      open: () =>
        corrupt
          ? Promise.reject(new Error("bad cipher"))
          : Promise.resolve(prepared),
      send: () => {
        sent++;
        return Promise.resolve("unexpected");
      },
      rpc: (name, args) => {
        if (name === "begin_email_send") {
          return Promise.resolve({
            disposition: "send",
            message: {
              prepared: {},
              recipient: "other@example.invalid",
              tracking_policy: "disabled",
            },
          });
        }
        finishes.push(args);
        return Promise.resolve({});
      },
    });
    assertEquals(sent, 0);
    assertEquals(result.disposition, "dead");
    assertEquals(finishes[0].p_error, "prepared_payload_invalid");
  }
});

Deno.test("SES signs an encoded email identity using the AWS double-escaped canonical path", async () => {
  const hex = (bytes: ArrayBuffer) =>
    Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, "0"))
      .join("");
  const hash = async (text: string) =>
    hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  const hmac = async (raw: Uint8Array<ArrayBuffer>, text: string) => {
    const key = await crypto.subtle.importKey(
      "raw",
      raw,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    return new Uint8Array(
      await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text)),
    );
  };
  const stub: typeof fetch = async (url, init) => {
    assertEquals(
      String(url),
      "https://email.eu-central-1.amazonaws.com/v2/email/identities/sender%40example.invalid",
    );
    const headers = init!.headers as Record<string, string>;
    const time = headers["x-amz-date"], date = time.slice(0, 8);
    const scope = `${date}/eu-central-1/ses/aws4_request`;
    const canonical = [
      "GET",
      "/v2/email/identities/sender%2540example.invalid",
      "",
      `content-type:application/json\nhost:email.eu-central-1.amazonaws.com\nx-amz-date:${time}\n`,
      "content-type;host;x-amz-date",
      await hash(""),
    ].join("\n");
    let key = await hmac(new TextEncoder().encode("AWS4fixture-only"), date);
    for (const part of ["eu-central-1", "ses", "aws4_request"]) {
      key = await hmac(key, part);
    }
    const signature = hex(
      (await hmac(
        key,
        ["AWS4-HMAC-SHA256", time, scope, await hash(canonical)].join("\n"),
      )).buffer,
    );
    assertEquals(
      headers.authorization,
      `AWS4-HMAC-SHA256 Credential=fixture/${scope}, SignedHeaders=content-type;host;x-amz-date, Signature=${signature}`,
    );
    return Response.json({ VerifiedForSendingStatus: true });
  };
  await sesRequest(
    config,
    "GET",
    "/v2/email/identities/sender%40example.invalid",
    null,
    stub,
  );
});

Deno.test("a preparation timeout keeps its permit until the renderer stops", async () => {
  let release!: (
    value: { prepared: unknown; postAction: Record<string, unknown> },
  ) => void;
  let claimed = false, finished = false;
  const work = new Promise<
    { prepared: unknown; postAction: Record<string, unknown> }
  >((resolve) => release = resolve);
  const drain = drainEmails({
    rpc: async (name) => {
      if (name === "claim_email") {
        if (claimed) return null;
        claimed = true;
        return {
          message_id: "fixture",
          attempt_id: "attempt",
          lease_token: "token",
          prepared: null,
        };
      }
      if (name === "finish_email_attempt") finished = true;
      return null;
    },
    prepare: () => work,
    seal: async (value) => value,
    gateway: async () => {
      throw Error("timed-out work must not send");
    },
    now: Date.now,
  }, 5);
  await new Promise((resolve) => setTimeout(resolve, 15));
  assertEquals(
    finished,
    false,
    "live renderer still owns global preparation capacity",
  );
  release({ prepared: {}, postAction: {} });
  await drain;
  assertEquals(finished, true);
});
Deno.test("only explicit permanent address DSN statuses report an invalid recipient", () => {
  const event = {
    eventType: "Bounce",
    mail: {
      messageId: "fixture",
      destination: ["fixture@example.invalid"],
      timestamp: "2026-10-04T00:00:00Z",
    },
    bounce: {
      bounceType: "Permanent",
      timestamp: "2026-10-04T00:00:01Z",
      bouncedRecipients: [{
        emailAddress: "fixture@example.invalid",
        status: "5.1.1",
      }],
    },
  };
  assertEquals(
    normalizeSesEvents(event, "topic", "event")[0].invalid_recipient,
    true,
  );
  event.bounce.bouncedRecipients[0].status = "5.2.2";
  assertEquals(
    normalizeSesEvents(event, "topic", "event")[0].invalid_recipient,
    false,
    "mailbox full is not an invalid address",
  );
  event.bounce.bounceType = "Transient";
  event.bounce.bouncedRecipients[0].status = "5.1.1";
  assertEquals(
    normalizeSesEvents(event, "topic", "event")[0].invalid_recipient,
    false,
  );
});

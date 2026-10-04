import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  sendSes,
  sesBody,
  type SesConfig,
  SesFailure,
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

import assert from "node:assert/strict";
import { renderEmail } from "./emailDelivery.ts";
import { emailRegistry, kindForTemplate } from "./emailRegistry.ts";
import { sha256Text, type WaitlistEmailSource } from "./waitlistEmail.ts";
import {
  renderWaitlistEmail,
  waitlistCapabilityUrl,
  waitlistCountPhrase,
  waitlistExpiryText,
  type WaitlistEmailRow,
  type WaitlistRenderContext,
} from "./waitlistEmailRenderer.ts";

const source: WaitlistEmailSource = {
  version: 1,
  templateCode: "waitlist_confirmation",
  token: "a".repeat(64),
  recipient: "synthetic@example.invalid",
  organization: 1,
  occasion: 2,
  unit: 3,
  occasionTitle: 'Festival <script>alert("x")</script> & music',
  participantCount: 4,
  formLink: "synthetic-form",
};
const sealed = { v: "1", iv: "mock", ciphertext: "source" };
const manageSealed = { ...sealed, ciphertext: "manage" };

async function fixture(offer = false) {
  const selected: WaitlistEmailSource = offer
    ? {
      ...source,
      templateCode: "waitlist_offer",
      orderId: 101,
      token: "b".repeat(64),
      offeredCount: 2,
      expiresAt: "2026-10-14T12:00:00Z",
    }
    : { ...source };
  const row: WaitlistEmailRow = {
    message_kind: selected.templateCode,
    code: selected.templateCode,
    recipient: selected.recipient,
    organization: 1,
    occasion: 2,
    unit: 3,
    order_id: 101,
    data: {
      order_id: 101,
      offer_id: offer ? "10000000-0000-4000-8000-000000000001" : null,
      content_hash: await sha256Text(JSON.stringify(selected)),
      waitlistEnvelope: sealed,
    },
  };
  const context: WaitlistRenderContext = {
    orderId: 101,
    orderSymbol: "COMMITTED123",
    organization: 1,
    occasion: 2,
    unit: 3,
    formLink: selected.formLink,
    webLink: "https://tenant.example.invalid/",
    tokenHash: await sha256Text(selected.token),
    offeredCount: offer ? 1 : undefined,
    participantCount: offer ? 3 : 4,
    expiresAt: selected.expiresAt,
    timeZone: "Europe/Prague",
    manageEnvelope: manageSealed,
    manageContentHash: await sha256Text(JSON.stringify(source)),
    manageTokenHash: await sha256Text(source.token),
  };
  const calls: string[] = [];
  const dependencies = {
    open: async (value: Record<string, string>) =>
      value.ciphertext === "manage" ? source : selected,
    context: async (
      orderId: number,
      offerId: string | null,
      recipient: string,
    ) => {
      assert.equal(orderId, 101);
      assert.equal(offerId, row.data.offer_id);
      assert.equal(recipient, selected.recipient);
      calls.push("context");
      return context;
    },
    render: (input: Parameters<typeof renderEmail>[0]) =>
      renderEmail(input, async (code, tenant) => {
        calls.push("resolver");
        assert.equal(code, selected.templateCode);
        assert.deepEqual(tenant, { organization: 1, occasion: 2, unit: 3 });
        return {
          template: {
            id: 1,
            subject: "{{order_symbol}}",
            html:
              "{{occasion_title}} {{participant_count}} {{manage_waitlist_button}} {{manage_waitlist_url}} {{offered_count}} {{offer_button}} {{offer_expires_at}}",
          },
          wrapper: {
            html: '<main data-wrapper="inherited">{{content}}</main>',
          },
        };
      }),
    now: () => Date.parse("2026-10-13T12:00:00Z"),
  };
  return { selected, row, context, calls, dependencies };
}

Deno.test("waitlist codes use the canonical sensitive registry", () => {
  for (const code of ["waitlist_confirmation", "waitlist_offer"] as const) {
    assert.equal(kindForTemplate(code), code);
    assert.equal(emailRegistry[code].sensitive, true);
  }
});

Deno.test("confirmation renders committed identity, safe text and inherited wrapper", async () => {
  const { row, dependencies, calls } = await fixture();
  const result = await renderWaitlistEmail(row, dependencies);
  assert.equal(result.prepared.subject, "COMMITTED123");
  assert.equal(result.prepared.to, row.recipient);
  assert.match(result.prepared.html, /data-wrapper="inherited"/);
  assert.match(result.prepared.html, /&lt;script&gt;/);
  assert.doesNotMatch(result.prepared.html, /<script>/);
  assert.match(result.prepared.html, /#waitlist\?order_id=101&amp;token=/);
  assert.match(result.prepared.html, /referrerpolicy="no-referrer"/);
  assert.deepEqual(result.postAction, { tracking_policy: "disabled" });
  assert.deepEqual(calls, ["context", "resolver"]);
});

Deno.test("offer renders distinct manage capability and current pending places", async () => {
  const { row, dependencies } = await fixture(true);
  const result = await renderWaitlistEmail(row, dependencies);
  assert.match(
    result.prepared.html,
    /offer_id=10000000-0000-4000-8000-000000000001&amp;token=bbbb/,
  );
  assert.match(result.prepared.html, /order_id=101&amp;token=aaaa/);
  assert.match(result.prepared.html, / 3 /);
  assert.match(result.prepared.html, / 1 <a /);
  assert.deepEqual(result.postAction, {
    tracking_policy: "disabled",
    waitlist_pending_count: 1,
  });
});

Deno.test("recipient, tenant, template, content digest and order tampering fail closed", async () => {
  for (
    const mutate of [
      (row: WaitlistEmailRow) => {
        row.recipient = "other@example.invalid";
      },
      (row: WaitlistEmailRow) => {
        row.organization = 99;
      },
      (row: WaitlistEmailRow) => {
        row.code = "waitlist_offer";
      },
      (row: WaitlistEmailRow) => {
        row.data.content_hash = "tampered";
      },
      (row: WaitlistEmailRow) => {
        row.order_id = 999;
      },
    ]
  ) {
    const { row, dependencies, calls } = await fixture();
    mutate(row);
    await assert.rejects(
      () => renderWaitlistEmail(row, dependencies),
      /binding_invalid/,
    );
    assert.deepEqual(calls, []);
  }
});

Deno.test("same-order capability substitution and foreign manage source fail closed", async () => {
  const f = await fixture(true);
  f.context.tokenHash = await sha256Text("c".repeat(64));
  await assert.rejects(
    () => renderWaitlistEmail(f.row, f.dependencies),
    /context_mismatch/,
  );
  const g = await fixture(true);
  g.context.manageTokenHash = await sha256Text("c".repeat(64));
  await assert.rejects(
    () => renderWaitlistEmail(g.row, g.dependencies),
    /manage_binding_invalid/,
  );
  const h = await fixture(true);
  delete h.context.manageEnvelope;
  await assert.rejects(
    () => renderWaitlistEmail(h.row, h.dependencies),
    /manage_source_missing/,
  );
});

Deno.test("expired, cancelled and fully consumed delayed offers never render", async () => {
  const expired = await fixture(true);
  expired.dependencies.now = () => Date.parse(expired.selected.expiresAt!);
  await assert.rejects(
    () => renderWaitlistEmail(expired.row, expired.dependencies),
    /offer_expired/,
  );
  assert.deepEqual(expired.calls, []);
  const consumed = await fixture(true);
  consumed.context.offeredCount = 0;
  await assert.rejects(
    () => renderWaitlistEmail(consumed.row, consumed.dependencies),
    /offer_context_invalid/,
  );
  const cancelled = await fixture(true);
  cancelled.dependencies.context = async () => {
    throw new Error("waitlist_email_source_invalid");
  };
  await assert.rejects(
    () => renderWaitlistEmail(cancelled.row, cancelled.dependencies),
    /source_invalid/,
  );
});

Deno.test("links permit trusted localhost previews and reject credentialed or unsafe bases", async () => {
  const { context, selected } = await fixture();
  const local = waitlistCapabilityUrl({
    ...context,
    webLink: "http://localhost:5173",
  }, selected);
  const url = new URL(local);
  assert.equal(url.search, "");
  assert.equal(url.pathname, "/form/synthetic-form");
  assert.match(url.hash, /^#waitlist\?order_id=101&token=/);
  for (
    const webLink of [
      "http://public.example.invalid",
      "https://user:pass@tenant.example.invalid",
      "javascript:alert(1)",
      "https://tenant.example.invalid?token=unsafe",
    ]
  ) {
    assert.throws(
      () => waitlistCapabilityUrl({ ...context, webLink }, selected),
      /origin_invalid/,
    );
  }
});

Deno.test("Czech complete person and place phrases cover one, few and many", () => {
  for (const [count, people, places] of [[1, "1 osobu", "1 místo"], [2, "2 osoby", "2 místa"], [5, "5 osob", "5 míst"], [21, "21 osob", "21 míst"]] as const) {
    assert.equal(waitlistCountPhrase(count, "person"), people);
    assert.equal(waitlistCountPhrase(count, "place"), places);
  }
});

Deno.test("offer expiry uses configured timezone through both DST boundaries", () => {
  const beforeSpring = waitlistExpiryText("2026-03-29T00:30:00Z", "Europe/Prague");
  const afterSpring = waitlistExpiryText("2026-03-29T01:30:00Z", "Europe/Prague");
  assert.match(beforeSpring, /01:30/);
  assert.match(afterSpring, /03:30/);
  assert.match(waitlistExpiryText("2026-10-25T00:30:00Z", "Europe/Prague"), /02:30/);
  assert.match(waitlistExpiryText("2026-10-25T01:30:00Z", "Europe/Prague"), /02:30/);
  assert.match(waitlistExpiryText("2026-10-14T12:00:00Z", "America/New_York"), /08:00/);
  assert.match(afterSpring, /Europe\/Prague/);
  assert.throws(() => waitlistExpiryText("2026-10-14T12:00:00Z", "not/a-zone"));
});

Deno.test("semantic phrases render alongside unchanged custom numeric placeholders", async () => {
  for (const count of [1, 2, 5]) {
    const f = await fixture(true);
    f.selected.offeredCount = count;
    f.selected.participantCount = count;
    f.context.offeredCount = count;
    f.context.participantCount = count;
    f.row.data.content_hash = await sha256Text(JSON.stringify(f.selected));
    f.dependencies.render = (input) => renderEmail(input, async () => ({
      template: {id: 1, subject: "{{offered_places}}", html: "{{participant_phrase}}|{{participant_count}}|{{offered_count}}|{{offer_expires_at}}"},
      wrapper: {html: "{{content}}"},
    }));
    const result = await renderWaitlistEmail(f.row, f.dependencies);
    assert.equal(result.prepared.subject, waitlistCountPhrase(count, "place"));
    assert.match(result.prepared.html, new RegExp(`${waitlistCountPhrase(count, "person")}\\|${count}\\|${count}\\|`));
    assert.match(result.prepared.html, /14:00 \(Europe\/Prague\)/);
  }
});

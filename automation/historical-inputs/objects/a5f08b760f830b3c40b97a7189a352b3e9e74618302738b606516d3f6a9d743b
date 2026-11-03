import assert from "node:assert/strict";
import { renderEmail } from "./emailDelivery.ts";
import { openEmail, sealEmail } from "./emailPayload.ts";
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
    toneSubstitutions: {
      waitlist_offer_button_single: "Potvrdit přihlášení",
      waitlist_offer_button_multiple: "Potvrdit vybrané osoby",
      waitlist_manage_button_label: "Spravovat čekání",
      waitlist_confirmation_heading: "Jste mezi náhradníky",
      waitlist_confirmation_explanation: "Zatím nic neplatíte. Jakmile se uvolní místo, pošleme vám nabídku. Čekání můžete spravovat nebo ukončit přes tento odkaz:",
      waitlist_offer_heading: "Máme pro vás nabídku",
      waitlist_offer_instructions_single: "Po otevření nabídky doplníte údaje a vyberete produkty podle aktuální dostupnosti. Přihlášení pak potvrdíte.",
      waitlist_offer_instructions: "Po otevření nabídky vyberete, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíte.",
    },
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
  assert.match(result.prepared.html, /\?order_id=101&amp;token=/);
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
  assert.equal(url.hash, "");
  assert.equal(url.pathname, "/order");
  assert.match(url.search, /^\?order_id=101&token=/);
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
  assert.ok(beforeSpring.includes("\u00a0"));
  assert.doesNotMatch(beforeSpring, /[ \t\n\r]/);
  assert.match(afterSpring, /03:30/);
  assert.match(waitlistExpiryText("2026-10-25T00:30:00Z", "Europe/Prague"), /02:30/);
  assert.match(waitlistExpiryText("2026-10-25T01:30:00Z", "Europe/Prague"), /02:30/);
  assert.match(waitlistExpiryText("2026-10-14T12:00:00Z", "America/New_York"), /08:00/);
  assert.doesNotMatch(afterSpring, /Europe|UTC|GMT/);
  const utcDate = waitlistExpiryText("2026-10-14T12:00:00Z", "UTC");
  assert.match(utcDate, /12:00/);
  assert.doesNotMatch(utcDate, /UTC|GMT/);
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
    assert.match(result.prepared.html, /14:00/);
    assert.doesNotMatch(result.prepared.html, /Europe\/Prague|UTC/);
  }
});

// Render the actual canonical default SQL templates through the same encrypted
// queue-source -> waitlist renderer -> inherited wrapper path as production.
for (const informal of [false, true]) {
  for (const count of [1, 2]) {
    for (const offer of [false, true]) {
     for (const offeredCount of offer && count === 2 ? [1, 2] : [count]) {
      Deno.test(`encrypted queued ${offer ? "offer" : "confirmation"} ${informal ? "informal" : "formal"} for ${count}, offered ${offeredCount}`, async () => {
        const previousKey = Deno.env.get("EMAIL_PAYLOAD_KEY");
        Deno.env.set("EMAIL_PAYLOAD_KEY", btoa(String.fromCharCode(...new Uint8Array(32).fill(7))));
        try {
          const sql = await Deno.readTextFile(new URL("../../../database/functions/eshop_waitlist/email_templates.sql", import.meta.url));
          const defaults = new Map([...sql.matchAll(/\('([^']+)','([^']+)',\s*'([^']+)'\)/g)]
            .map((match) => [match[1], { id: 1, subject: match[2], html: match[3] }]));
          const f = await fixture(offer);
          f.selected.participantCount = count;
          f.context.participantCount = count;
          f.context.communicationTone = informal ? "informal" : "formal";
          if (informal) f.context.toneSubstitutions = {
            waitlist_offer_button_single: "Potvrdit přihlášení",
            waitlist_offer_button_multiple: "Potvrdit vybrané osoby",
            waitlist_manage_button_label: "Spravovat čekání",
            waitlist_confirmation_heading: "Jsi mezi náhradníky",
            waitlist_confirmation_explanation: "Zatím nic neplatíš. Jakmile se uvolní místo, pošleme ti nabídku. Čekání můžeš spravovat nebo ukončit přes tento odkaz:",
            waitlist_offer_heading: "Máme pro tebe nabídku",
            waitlist_offer_instructions_single: "Po otevření nabídky doplníš údaje a vybereš produkty podle aktuální dostupnosti. Přihlášení pak potvrdíš.",
            waitlist_offer_instructions: "Po otevření nabídky vybereš, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíš.",
          };
          f.context.timeZone = "UTC"; // Even this configured zone has no visible suffix.
          if (offer) {
            f.selected.offeredCount = offeredCount;
            f.context.offeredCount = offeredCount;
          }
          f.row.data.content_hash = await sha256Text(JSON.stringify(f.selected));
          f.row.data.waitlistEnvelope = await sealEmail(f.selected);
          f.context.manageEnvelope = await sealEmail(source);
          const result = await renderWaitlistEmail(f.row, {
            ...f.dependencies,
            open: (value) => openEmail<WaitlistEmailSource>(value),
            render: (input) => renderEmail(input, async (code) => ({
              template: defaults.get(code),
              wrapper: { html: '<main data-wrapper="inherited">{{content}}</main>' },
            })),
          });
          assert.match(result.prepared.html, /data-wrapper="inherited"/);
          assert.ok(result.prepared.html.includes(waitlistCountPhrase(offer ? offeredCount : count, offer ? "place" : "person")));
          assert.match(result.prepared.html, /COMMITTED123/);
          assert.doesNotMatch(result.prepared.html, /\{\{|\bUTC\b/);
          if (offer) {
            assert.ok(result.prepared.html.includes(offeredCount === 1 ? "Potvrdit přihlášení" : "Potvrdit vybrané osoby"));
            assert.doesNotMatch(result.prepared.html, /Otevřít nabídku|Spravovat čekání/);
            const dateChunk = result.prepared.html.match(/<span style="white-space:nowrap">([^<]+)<\/span>/)?.[1];
            assert.ok(dateChunk && dateChunk.includes("\u00a0"));
            assert.doesNotMatch(dateChunk!, /[ \t\n\r]/);
            assert.ok(result.prepared.html.includes(informal ? "Máme pro tebe nabídku" : "Máme pro vás nabídku"));
            if (count === 1 && offeredCount === 1) {
              assert.ok(result.prepared.html.includes(informal ? "doplníš údaje" : "doplníte údaje"));
              assert.ok(result.prepared.html.includes(informal ? "Přihlášení pak potvrdíš" : "Přihlášení pak potvrdíte"));
              assert.doesNotMatch(result.prepared.html, /kdo přijde/);
            } else {
              assert.ok(result.prepared.html.includes(informal ? "vybereš, kdo přijde" : "vyberete, kdo přijde"));
            }
            assert.ok(result.prepared.html.includes(informal ? "potvrdíš" : "potvrdíte"));
            assert.doesNotMatch(result.prepared.html, informal ? /pro vás|vyberete|potvrdíte/ : /pro tebe|vybereš|potvrdíš/);
          } else {
            assert.match(result.prepared.html, /Spravovat čekání/);
            assert.ok(result.prepared.html.includes(informal ? "Jsi mezi náhradníky" : "Jste mezi náhradníky"));
            assert.ok(result.prepared.html.includes(informal ? "nic neplatíš" : "nic neplatíte"));
            assert.ok(result.prepared.html.includes(informal ? "pošleme ti" : "pošleme vám"));
            assert.ok(result.prepared.html.includes(informal ? "můžeš" : "můžete"));
            assert.doesNotMatch(result.prepared.html, informal ? /Jste|neplatíte|pošleme vám|můžete/ : /Jsi|neplatíš|pošleme ti|můžeš/);
          }
        } finally {
          if (previousKey === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
          else Deno.env.set("EMAIL_PAYLOAD_KEY", previousKey);
        }
      });
     }
    }
  }
}
Deno.test("informal communication setting does not rewrite an authored formal template", async () => {
  const f = await fixture();
  f.context.communicationTone = "informal";
  const authored = "Vážení zákazníci, prosíme vás o trpělivost. Vlastní text pořadatele.";
  const result = await renderWaitlistEmail(f.row, {
    ...f.dependencies,
    render: (input) => renderEmail(input, async () => ({
      template: { id: 10, subject: "Vlastní předmět pořadatele", html: authored },
    })),
  });
  assert.equal(result.prepared.html, authored);
  assert.equal(result.prepared.subject, "Vlastní předmět pořadatele");
});

Deno.test("overview remains optional in inherited waitlist mail and explicit insertion works", async () => {
  const { prepareOrderOverviewSource } = await import("./waitlistEmail.ts");
  const previous = Deno.env.get("EMAIL_PAYLOAD_KEY");
  Deno.env.set("EMAIL_PAYLOAD_KEY", btoa(String.fromCharCode(...new Uint8Array(32).fill(23))));
  try {
    const f = await fixture();
    const legacy = await renderWaitlistEmail(f.row, f.dependencies);
    assert.equal(legacy.prepared.html.includes("#order?"), false);
    const selected = { ...source, version: 2 as const };
    f.row.data.content_hash = await sha256Text(JSON.stringify(selected));
    f.context.overviewSource = await prepareOrderOverviewSource(source);
    const rendered = await renderWaitlistEmail(f.row, { ...f.dependencies, open: async () => selected });
    assert.doesNotMatch(rendered.prepared.html, /Zobrazit aktuální stav objednávky/);
    const explicit = await renderWaitlistEmail(f.row, {
      ...f.dependencies, open: async () => selected,
      render: (input) => renderEmail(input, async () => ({
        template: { id: 1, subject: "Waitlist", html: "{{order_overview_button}}" },
        wrapper: { html: '<main style="padding:24px">{{content}}</main>' },
      })),
    });
    assert.match(explicit.prepared.html, /\?order_id=101&amp;token=[a-f0-9]{64}/);
    assert.equal(rendered.postAction.tracking_policy, "disabled");
  } finally {
    if (previous === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY"); else Deno.env.set("EMAIL_PAYLOAD_KEY", previous);
  }
});

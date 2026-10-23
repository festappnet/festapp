import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  escapeTicketText,
  inlineTicketBlock,
  issuableTickets,
  prepareTicketDelivery,
  qrPng,
  ticketDeliveryMode,
} from "./ticketDelivery.ts";
import { renderEmail } from "./emailDelivery.ts";
import { openEmail, sealEmail } from "./emailPayload.ts";
import { sesBody, type SesConfig } from "./sesProvider.ts";
const tickets = [2, 1].map((id) => ({
  id,
  occasion: 7,
  state: "paid",
  ticket_symbol: `symbol-${id}`,
}));
const config: SesConfig = {
  sender: "sender@example.invalid",
  region: "test",
  accessKey: "stub",
  secretKey: "stub",
  transactionalSet: "transactional",
  securitySet: "security",
  maxBytes: 1_000_000,
};
Deno.test("closed default contract and common admission selection", () => {
  assertEquals(ticketDeliveryMode({}), "pdf_attachment");
  for (const mode of [null, "", "invalid", 1]) {
    assertThrows(() => ticketDeliveryMode({ delivery_mode: mode }));
  }
  assertEquals(
    issuableTickets(
      [...tickets, { state: "storno" }, { state: "waitlisted" }],
      7,
    ),
    [...tickets].reverse(),
  );
  assertThrows(() => issuableTickets([{ ...tickets[0], occasion: 8 }], 7));
  assertThrows(() =>
    issuableTickets([{ ...tickets[0], ticket_symbol: null }], 7)
  );
  assertThrows(() => issuableTickets([{ state: "waitlisted" }], 7));
});
Deno.test("all delivery modes share exact symbols, CID transport, wrapper and immutable snapshot", async () => {
  for (const mode of ["pdf_attachment", "inline_qr", "both"]) {
    const pdfSymbols: string[] = [], qrSymbols: string[] = [];
    let pdfLoads = 0;
    const delivery = await prepareTicketDelivery(
      {
        id: 7,
        features: [{ code: "ticket", is_enabled: true, delivery_mode: mode }],
      },
      {},
      tickets,
      async () => {
        pdfLoads++;
        return async (ticket) => {
          pdfSymbols.push(ticket.ticket_symbol);
          return { bytes: new Uint8Array([1, 2, 3]) };
        };
      },
      async (symbol) => {
        qrSymbols.push(symbol);
        return await qrPng(symbol);
      },
    );
    assertEquals(pdfLoads, mode === "inline_qr" ? 0 : 1);
    assertEquals(
      pdfSymbols,
      mode === "inline_qr" ? [] : ["symbol-1", "symbol-2"],
    );
    assertEquals(
      qrSymbols,
      mode === "pdf_attachment" ? [] : ["symbol-1", "symbol-2"],
    );
    const prepared = await renderEmail(
      {
        to: "preview@example.invalid",
        from: config.sender,
        replyTo: config.sender,
        context: { organization: 1 },
        substitutions: {},
        attachments: delivery.attachments,
        ticketBlock: delivery.html,
      },
      async () => ({
        template: {
          id: 1,
          subject: "Tickets",
          html: "before{{tickets}}middle{{tickets}}after",
        },
        wrapper: { html: "<main>{{content}}</main>" },
      }),
    );
    assertEquals(prepared.html.includes("{{tickets}}"), false);
    assertEquals(
      (prepared.html.match(/<img /g) ?? []).length,
      qrSymbols.length,
    );
    assertEquals(prepared.html.startsWith("<main>before"), true);
    Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("k".repeat(32)));
    const restored = await openEmail<typeof prepared>(
      await sealEmail(prepared),
    );
    assertEquals(restored, prepared);
    const body = sesBody(restored, config, {}, false).Content.Simple;
    assertEquals(
      body.Attachments.filter((a) => a.ContentDisposition === "INLINE").length,
      qrSymbols.length,
    );
    for (
      const attachment of body.Attachments.filter((a) =>
        a.ContentDisposition === "INLINE"
      )
    ) {
      assertEquals(prepared.html.includes(`cid:${attachment.ContentId}`), true);
      assertEquals(attachment.ContentType, "image/png");
    }
    assertThrows(() =>
      sesBody(restored, { ...config, maxBytes: 4096 }, {}, false)
    );
  }
});
Deno.test("QR-only requires no PDF resources, disabled feature creates no assets, failure is atomic", async () => {
  const pdf = () => {
    throw new Error("must not load pdf");
  };
  const occasion = {
    id: 7,
    features: [{
      code: "ticket",
      is_enabled: true,
      delivery_mode: "inline_qr",
    }],
  };
  assertEquals(
    (await prepareTicketDelivery(occasion, {}, tickets, pdf)).attachments
      .length,
    2,
  );
  occasion.features[0].is_enabled = false;
  assertEquals(
    (await prepareTicketDelivery(occasion, {}, tickets, pdf, () => {
      throw new Error("no QR");
    })).attachments.length,
    0,
  );
  occasion.features[0].is_enabled = true;
  await assertRejects(
    () =>
      prepareTicketDelivery(occasion, {}, tickets, pdf, async (symbol) => {
        if (symbol === "symbol-2") throw new Error("item failed");
        return new Uint8Array([1]);
      }),
    Error,
    "item failed",
  );
});
Deno.test("20-ticket upper bound fits well below provider size and symbols cannot escape into HTML", async () => {
  const symbols = Array.from(
    { length: 20 },
    (_, i) => `FESTAPP-${i}-` + "x".repeat(32),
  );
  const block = await inlineTicketBlock(symbols);
  const prepared = await renderEmail(
    {
      to: "preview@example.invalid",
      from: config.sender,
      replyTo: config.sender,
      context: { organization: 1 },
      substitutions: {},
      attachments: block.attachments,
      ticketBlock: block.html,
    },
    async () => ({
      template: { id: 1, subject: "Tickets", html: "<p>Text</p>" },
    }),
  );
  const wire = sesBody(prepared, config, {}, false);
  assertEquals(JSON.stringify(wire).length < 200_000, true);
  const unsafe = await inlineTicketBlock(['"><script>alert(1)</script>']);
  assertEquals(unsafe.html.includes("<script>"), false);
});

Deno.test("payment notice using the shared paid template never issues inline tickets", async () => {
  const prepared = await renderEmail(
    {
      to: "preview@example.invalid",
      templateCode: "TICKET_ORDER_PAYMENT_DONE",
      context: { organization: 1 },
      substitutions: {},
    },
    async () => ({
      template: { id: 1, subject: "Paid", html: "before{{tickets}}after" },
    }),
  );
  assertEquals(prepared.html, "beforeafter");
  assertEquals(prepared.attachments, []);
});

Deno.test("inline MIME identifiers are unique across preparations and safe for HTML", async () => {
  const first = await inlineTicketBlock(["existing-ticket-symbol"]);
  const second = await inlineTicketBlock(["existing-ticket-symbol"]);
  const cid = first.attachments[0].contentId!;
  assertEquals(/^[a-z0-9@.-]+$/.test(cid), true);
  assertEquals(cid === second.attachments[0].contentId, false);
  assertEquals(first.html.includes(`cid:${cid}`), true);
});

Deno.test("inline admission tickets explain entry and show each escaped ticket code", async () => {
  const symbols = ["A1B2C3", '<ticket code="unsafe">&'];
  const block = await inlineTicketBlock(symbols);
  assertEquals(block.html.includes("Vstupenka 1 z 2"), true);
  assertEquals(block.html.includes("Vstupenka 2 z 2"), true);
  assertEquals(block.html.includes("QR 1 z 2"), false);
  assertEquals(
    (block.html.match(/U vstupu ukažte tento QR kód/g) ?? []).length,
    2,
  );
  assertEquals((block.html.match(/Kód vstupenky:/g) ?? []).length, 2);
  for (const [i, symbol] of symbols.entries()) {
    assertEquals(block.html.includes(escapeTicketText(symbol)), true);
    assertEquals(block.attachments[i].content, await qrPng(symbol));
    assertEquals(block.attachments[i].contentId?.includes(symbol), false);
  }
  assertEquals(block.html.includes('<ticket code="unsafe">'), false);
  const single = await inlineTicketBlock(["A1B2C3"], true);
  assertEquals(single.html.includes("Vaše vstupenka"), true);
  assertEquals(single.html.includes("Toto je vaše vstupenka."), true);
  assertEquals(single.html.includes("PDF příloze"), true);
});

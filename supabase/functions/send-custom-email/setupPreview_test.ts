import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  type SetupPreviewDependencies,
  setupPreviewResponse,
} from "./setupPreview.ts";
const input = {
  draftId: "00000000-0000-4000-8000-000000000001",
  tickets: [{ products: [3] }, { products: [4] }],
  fields: { name: "Jana", email: "preview@example.invalid" },
  locale: "cs",
};
function fixture() {
  const calls: string[] = [];
  const row = {
    unit: 2,
    data: {
      title: "Nová akce",
      communicationTone: "formal",
      deadline: "3",
      bankAccountId: 7,
      formDraft: {
        fields: [{ type: "ticket" }, {
          type: "product_type",
          product_type_data: {
            title: "Vstupné",
            products: [{
              id: 3,
              title: "Dospělý",
              price: 450,
              currency_code: "CZK",
            }, { id: 4, title: "Student", price: 350, currency_code: "CZK" }],
          },
        }],
      },
    },
  };
  const deps: SetupPreviewDependencies = {
    senderAddress: "sender@example.invalid",
    draft: async () => {
      calls.push("draft");
      return row;
    },
    catalog: async () => {
      calls.push("catalog");
      return { unit: { id: 2, data: {} }, organization: { id: 1 } };
    },
    sourceTemplates: async () => null,
    bank: async () => {
      calls.push("bank");
      return "123/0100";
    },
    resolve: async (code) => {
      calls.push(code);
      return {
        template: {
          id: 1,
          subject: "{{occasionTitle}} {{amount}}",
          html: "<main>{{fullOrder}}{{balanceReasoning}}</main>",
        },
        wrapper: { html: "<div>{{content}}</div>" },
      };
    },
  };
  return { deps, calls, row };
}
Deno.test("setup order preview authenticates and bounds input before any read", async () => {
  const f = fixture();
  assertEquals((await setupPreviewResponse(input, "", f.deps)).status, 401);
  for (
    const invalid of [{ draftId: "bad" }, { tickets: [null] }, {
      tickets: [{ products: ["foreign"] }],
    }, { tickets: Array(101).fill({ products: [] }) }]
  ) {
    assertEquals(
      (await setupPreviewResponse(
        { ...input, ...invalid },
        "Bearer user",
        f.deps,
      )).status,
      400,
    );
  }
  assertEquals(
    (await setupPreviewResponse(
      { ...input, extra: "x".repeat(40000) },
      "Bearer user",
      f.deps,
    )).status,
    413,
  );
  assertEquals(f.calls, []);
});
Deno.test("denied and terminal draft previews never render or look up an email scope", async () => {
  const f = fixture();
  f.deps.draft = async () => null;
  assertEquals(
    (await setupPreviewResponse(input, "Bearer user", f.deps)).status,
    403,
  );
  assertEquals(f.calls, []);
  f.deps.draft = async () => ({ unit: 2, data: { finalizedOccasion: 99 } });
  assertEquals(
    (await setupPreviewResponse(input, "Bearer user", f.deps)).status,
    403,
  );
  assertEquals(f.calls, []);
});
Deno.test("preview uses all selected products and canonical production email rendering without issuing orders", async () => {
  const f = fixture();
  const response = await setupPreviewResponse(input, "Bearer user", f.deps);
  assertEquals(response.status, 200);
  const result = await response.json();
  assertEquals(result.total, 800);
  assertEquals(result.messages.length, 2);
  assert(result.messages[0].html.includes("Dospělý"));
  assert(result.messages[0].html.includes("Student"));
  assert(result.messages[0].html.includes("preview@example.invalid"));
  assert(!result.messages[0].html.includes("5W8H2U8I9W"));
  assertEquals(f.calls, [
    "draft",
    "catalog",
    "bank",
    "TICKET_ORDER_CONFIRMATION",
    "TICKET_ORDER_PAYMENT_DONE",
  ]);
});
Deno.test("preview rejects foreign products and uses production Czech fallback for unsupported email locales", async () => {
  const f = fixture();
  assertEquals(
    (await setupPreviewResponse(
      { ...input, tickets: [{ products: [999] }] },
      "Bearer user",
      f.deps,
    )).status,
    400,
  );
  const result = await (await setupPreviewResponse(
    { ...input, locale: "sk" },
    "Bearer user",
    f.deps,
  )).json();
  assertEquals(result.locale, "cs");
});
Deno.test("zero price preview does not invent a paid confirmation and escapes customer HTML", async () => {
  const f = fixture();
  const response = await setupPreviewResponse(
    { ...input, tickets: [], fields: { name: "<img src=x>" } },
    "Bearer user",
    f.deps,
  );
  const result = await response.json();
  assertEquals(result.messages.length, 1);
  assertEquals(result.total, 0);
  assert(!result.messages[0].html.includes("<img src=x>"));
});

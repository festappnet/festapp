import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { createFakturoidGateway } from "./fakturoid.ts";
import { prepareFakturoidTicketOrder } from "./fakturoidPreparation.ts";
import { presentPayment } from "../_shared/paymentPresentation.ts";

for (const replacement of [false, true]) {
  Deno.test(`Fakturoid CZK reference reaches checkout QR after ${replacement ? "replacement" : "ordinary"} completion`, async () => {
    const order = {
      id: 12,
      payment_info: {
        payment_method: "bank",
        amount: 100,
        currency_code: "CZK",
        variable_symbol: "4830",
        account_number: "CZ6508000000192000145399",
        account_number_human_readable: "19-2000145399/0800",
      },
    };
    const config = { client_id: "test", client_secret: "test", slug: "test", subject_id: 1 };
    const gateway = createFakturoidGateway((async (input, init) => {
      if (String(input).endsWith("/oauth/token")) return Response.json({ access_token: "token" });
      if (!init?.method) return Response.json([]);
      assertEquals(JSON.parse(String(init.body)).variable_symbol, undefined);
      return Response.json({ id: 55, variable_symbol: "20260950" });
    }) as typeof fetch);
    const completions: string[] = [];
    const client = { rpc: async (name: string, params: Record<string, unknown>) => {
      if (name === "get_external_services") return { data: [{ type: "FAKTUROID", data: config }], error: null };
      if (name === "get_fakturoid_ticket_order_state_v1") return { data: "preparing_payment", error: null };
      if (name === "claim_replacement_invoice_preparation") return { data: { status: "claimed", token: "lease", allowCreate: true }, error: null };
      if (name === "mark_replacement_invoice_dispatch") return { data: null, error: null };
      assertEquals(params.p_variable_symbol, 20260950);
      completions.push(name);
      return { data: 20260950, error: null };
    } };
    assertEquals(await prepareFakturoidTicketOrder({ client, gateway, order, commandId: "same", unitName: "Event", replacement }), { ok: true });
    assertEquals(completions, [replacement ? "complete_replacement_invoice_preparation" : "complete_fakturoid_ticket_order_v1"]);
    assertEquals(order.payment_info.variable_symbol, "20260950");
    const payment = presentPayment(order.payment_info);
    assertEquals(payment.referenceDisplay, "20260950");
    assertStringIncludes(payment.qrPayload, "*X-VS:20260950");
  });
}

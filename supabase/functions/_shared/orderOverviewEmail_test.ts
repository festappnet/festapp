import assert from "node:assert/strict";
import { prepareOrderOverviewEmail } from "./orderOverviewEmail.ts";
Deno.test("editor redelivery prepares inherited template with escaped capability and context", async () => {
  let captured: any;
  const result = await prepareOrderOverviewEmail({ recipient: "test@example.invalid", organization: 1, occasion: 2, unit: 3,
    occasionTitle: "<script>event</script>", orderSymbol: "A&B", formLink: "form", participantCount: 1 },
    "https://tenant.example.invalid/form/example#order?order_id=1&token=synthetic", async input => {
      captured = input; return { p_sealed: { ciphertext: "sealed-test" }, p_content_hash: "a".repeat(64) };
    });
  assert.equal(captured.templateCode, "ORDER_OVERVIEW");
  assert.deepEqual(captured.context, { organization: 1, occasion: 2, unit: 3 });
  assert.equal(captured.substitutions.occasion_title, "&lt;script&gt;event&lt;/script&gt;");
  assert.equal(captured.substitutions.order_symbol, "A&amp;B");
  assert.match(captured.substitutions.order_overview_button, /referrerpolicy="no-referrer"/);
  assert.match(captured.substitutions.order_overview_button, /order_id=1&amp;token=synthetic/);
  assert.equal(JSON.stringify(result).includes("synthetic"), false);
});

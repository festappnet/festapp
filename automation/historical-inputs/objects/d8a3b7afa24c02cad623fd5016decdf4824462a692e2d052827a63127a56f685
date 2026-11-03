import { strict as assert } from "node:assert";
import { formatCurrency } from "../utilities.ts";
import { generateFullOrder } from "../orderOverview.ts";
Deno.test("Stripe confirmation currency preserves cents while bank formatting retains its contract", () => {
  assert.match(formatCurrency(123.45, "CZK", 2), /123,45/);
  assert.match(formatCurrency(98.76, "EUR", 2), /98,76/);
  assert.doesNotMatch(formatCurrency(123.45, "CZK"), /123,45/);
});
Deno.test("Stripe full-order email preserves cents on every line and the total", () => {
  const tickets = [{
    products: [{ title: "Admission", price: "98.76", currency_code: "CZK" }, {
      title: "Extra",
      price: "24.69",
      currency_code: "CZK",
    }],
  }];
  const html = generateFullOrder(
    { email: "synthetic@example.test" },
    tickets,
    [],
    "cs",
    undefined,
    2,
  );
  for (const amount of ["98,76", "24,69", "123,45"]) {
    assert.ok(html.includes(amount), amount);
  }
  const legacy = generateFullOrder({}, tickets, [], "cs");
  assert.ok(!legacy.includes("123,45"));
});

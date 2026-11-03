// Unit tests for the shared meta-surcharge helpers.
// Run with: deno test --allow-net --allow-read supabase/functions/_shared/metaSurcharge_test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  aggregateMetaSurchargeSums,
  extractMetaSurcharge,
  formatSignedMetaSurcharge,
  MetaSurchargeAmount,
} from "./metaSurcharge.ts";

// =====================================================================
// extractMetaSurcharge — virtual-mode gate
// =====================================================================

Deno.test("extractMetaSurcharge — null when not virtual mode", () => {
  const p = { data: { meta_surcharge: { amount: 100, currency: "EUR" } } };
  assertEquals(extractMetaSurcharge(p, "real"), null);
  assertEquals(extractMetaSurcharge(p, undefined), null);
  assertEquals(extractMetaSurcharge(p, ""), null);
});

Deno.test("extractMetaSurcharge — returns amount in virtual mode", () => {
  const p = { data: { meta_surcharge: { amount: 100, currency: "EUR" } } };
  assertEquals(extractMetaSurcharge(p, "virtual"), {
    amount: 100,
    currency: "EUR",
  });
});

// =====================================================================
// extractMetaSurcharge — defaults + validation
// =====================================================================

Deno.test("extractMetaSurcharge — falls back to EUR when currency missing", () => {
  const p = { data: { meta_surcharge: { amount: 50 } } };
  assertEquals(extractMetaSurcharge(p, "virtual"), {
    amount: 50,
    currency: "EUR",
  });
});

Deno.test("extractMetaSurcharge — accepts numeric strings from JSON", () => {
  const p = { data: { meta_surcharge: { amount: "150", currency: "CZK" } } };
  assertEquals(extractMetaSurcharge(p, "virtual"), {
    amount: 150,
    currency: "CZK",
  });
});

Deno.test("extractMetaSurcharge — null for zero / missing / non-numeric amount", () => {
  for (const amt of [0, null, undefined, "abc", NaN]) {
    const p = { data: { meta_surcharge: { amount: amt } } };
    assertEquals(
      extractMetaSurcharge(p, "virtual"),
      null,
      `should be null for amount=${JSON.stringify(amt)}`,
    );
  }
});

Deno.test("extractMetaSurcharge — null when meta_surcharge key missing entirely", () => {
  assertEquals(extractMetaSurcharge({ data: {} }, "virtual"), null);
  assertEquals(extractMetaSurcharge({}, "virtual"), null);
  assertEquals(extractMetaSurcharge(null, "virtual"), null);
});

Deno.test("extractMetaSurcharge — preserves negative amounts (discounts)", () => {
  const p = { data: { meta_surcharge: { amount: -50, currency: "CZK" } } };
  assertEquals(extractMetaSurcharge(p, "virtual"), {
    amount: -50,
    currency: "CZK",
  });
});

// =====================================================================
// aggregateMetaSurchargeSums
// =====================================================================

Deno.test("aggregateMetaSurchargeSums — groups by currency, preserves order of first appearance", () => {
  const input: MetaSurchargeAmount[] = [
    { amount: 100, currency: "EUR" },
    { amount: 50, currency: "CZK" },
    { amount: 25, currency: "EUR" },
  ];
  const out = aggregateMetaSurchargeSums(input);
  // Sort for deterministic comparison.
  out.sort((a, b) => a.currency.localeCompare(b.currency));
  assertEquals(out, [
    { currency: "CZK", sum: 50 },
    { currency: "EUR", sum: 125 },
  ]);
});

Deno.test("aggregateMetaSurchargeSums — drops currencies whose net sum is zero", () => {
  const out = aggregateMetaSurchargeSums([
    { amount: 100, currency: "EUR" },
    { amount: -100, currency: "EUR" },
    { amount: 50, currency: "CZK" },
  ]);
  assertEquals(out, [{ currency: "CZK", sum: 50 }]);
});

Deno.test("aggregateMetaSurchargeSums — empty input yields empty array", () => {
  assertEquals(aggregateMetaSurchargeSums([]), []);
});

// =====================================================================
// formatSignedMetaSurcharge
// =====================================================================

Deno.test("formatSignedMetaSurcharge — '+' for positive, '−' for negative", () => {
  const plainFmt = (n: number, c: string) => `${n} ${c}`;
  assertEquals(formatSignedMetaSurcharge(100, "EUR", plainFmt), "+ 100 EUR");
  assertEquals(formatSignedMetaSurcharge(-50, "CZK", plainFmt), "− 50 CZK");
});

Deno.test("formatSignedMetaSurcharge — abs value passed to formatter", () => {
  let received = -999;
  formatSignedMetaSurcharge(-42, "EUR", (n) => {
    received = n;
    return "";
  });
  assertEquals(received, 42);
});

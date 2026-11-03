import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildEpcSctPayload,
  buildSpdPayload,
  isValidCreditorReference,
  presentPayment,
} from "./paymentPresentation.ts";

Deno.test("CZK presentation preserves SPD and numeric VS", () => {
  const payment = {
    amount: 123.4,
    currency_code: "CZK",
    account_number: "CZ6508000000192000145399",
    variable_symbol: 12345,
  };
  assertEquals(
    buildSpdPayload(payment),
    "SPD*1.0*ACC:CZ6508000000192000145399*AM:123.40*CC:CZK*X-VS:12345",
  );
  assertEquals(presentPayment(payment).referenceKind, "VS");
});

Deno.test("EUR presentation emits structured RF and no unstructured remittance", () => {
  const payment = {
    amount: 12.3,
    currency_code: "EUR",
    account_number: "DE71110220330123456789",
    creditor_name: "Franz Mustermann",
    creditor_reference: "RF18539007547034",
  };
  const payload = buildEpcSctPayload(payment);
  assertEquals(payload.split("\n"), [
    "BCD",
    "002",
    "1",
    "SCT",
    "",
    "Franz Mustermann",
    "DE71110220330123456789",
    "EUR12.30",
    "",
    "RF18539007547034",
    "",
    "",
  ]);
  assertEquals(presentPayment(payment).referenceKind, "RF");
});

Deno.test("EUR presentation fails closed without creditor data", () => {
  assertThrows(
    () =>
      buildEpcSctPayload({
        amount: 1,
        currency_code: "EUR",
        account_number: "DE71110220330123456789",
        creditor_reference: "RF18539007547034",
      }),
    Error,
    "INVALID_EPC_PAYMENT_DATA",
  );
});

Deno.test("EUR presentation keeps Czech names and removes EPC field separators", () => {
  const payload = buildEpcSctPayload({
    amount: 12.3,
    currency_code: "EUR",
    account_number: "DE71110220330123456789",
    creditor_name: " Hvězda\nMořská ",
    creditor_reference: "RF18539007547034",
  });
  assertEquals(payload.split("\n")[5], "Hvězda Mořská");
  assertEquals(payload.split("\n")[9], "RF18539007547034");
});

Deno.test("RF validation rejects a changed checksum payload", () => {
  assertEquals(isValidCreditorReference("RF18539007547034"), true);
  assertEquals(isValidCreditorReference("RF18539007547035"), false);
});

import { assertEquals, assertThrows } from "jsr:@std/assert";
import { parseAgreementConfig } from "./agreementConfig.ts";

const service = {
  type: "AGREEMENT_PDF",
  data: {
    organizer: {
      name: "Fixture Travel",
      ico: "00000000",
      dic: "CZ00000000",
      address: "Fixture street 1",
      email: "fixture@example.invalid",
      phone: "+420 000 000 000",
      account: "Fixture account",
    },
    paymentClause: "Fixture payment clause",
    termsClause: "Fixture terms clause",
    logoUrl: "https://assets.example.invalid/logo.png",
    fontUrl: "https://assets.example.invalid/font.ttf",
  },
};

Deno.test("agreement config reads the canonical external service", () => {
  assertEquals(parseAgreementConfig([service]).organizer.name, "Fixture Travel");
});

Deno.test("agreement config fails closed without tenant data", () => {
  assertThrows(() => parseAgreementConfig([]), Error, "agreement_config_missing_service");
  assertThrows(() => parseAgreementConfig([{ ...service, data: { ...service.data, logoUrl: "file:///tmp/logo" } }]), Error, "agreement_config_invalid_logo_url");
});

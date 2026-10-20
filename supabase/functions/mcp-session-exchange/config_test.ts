import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseMcpTenants } from "./config.ts";
const one = { tenantId: "one", tenantOrigin: "https://one.invalid", organizationId: 3,
  issuer: "https://mcp.invalid", brokerSecret: "s".repeat(43) };
Deno.test("tenant registry preserves distinct first-party origin, organization and issuer bindings", () => {
  const two = { ...one, tenantId: "two", tenantOrigin: "https://two.invalid", organizationId: 4, brokerSecret: "t".repeat(43) };
  const registry = parseMcpTenants(JSON.stringify([one, two]));
  assertEquals(registry.find(t => t.tenantOrigin === two.tenantOrigin), two);
  assertEquals(registry.find(t => t.tenantOrigin === "https://evil.invalid"), undefined);
  assertEquals(registry.find(t => t.tenantOrigin === "https://one.invalid.evil.invalid"), undefined);
});
Deno.test("tenant registry rejects ambiguous origins, insecure issuers and incomplete tenant identities", () => {
  for (const raw of [[], [one, one], [{ ...one, tenantOrigin: "http://one.invalid" }],
    [{ ...one, tenantOrigin: "https://one.invalid/path" }], [{ ...one, issuer: "https://user@mcp.invalid" }],
    [{ ...one, organizationId: 0 }], [{ ...one, brokerSecret: "short" }], [{ ...one, tenantId: "" }]]) {
    assertThrows(() => parseMcpTenants(JSON.stringify(raw)));
  }
});

import { assertEquals, assertThrows } from "jsr:@std/assert";
import { parseOrganizationBranding } from "./organizationBranding.ts";

Deno.test("organization branding normalizes the public app URL", () => {
  assertEquals(parseOrganizationBranding({ APP_NAME: "Tenant App", DEFAULT_URL: "https://tenant.example/" }), {
    appName: "Tenant App",
    defaultUrl: "https://tenant.example",
  });
});

Deno.test("organization branding fails closed when required public inputs are absent", () => {
  assertThrows(() => parseOrganizationBranding({ APP_NAME: "Tenant App" }), Error, "organization_branding_missing");
  assertThrows(() => parseOrganizationBranding({ APP_NAME: "Tenant App", DEFAULT_URL: "file:///tmp/app" }), Error, "organization_branding_invalid_url");
});

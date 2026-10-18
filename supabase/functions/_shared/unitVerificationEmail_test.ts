import { assertEquals, assertStringIncludes, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { unitVerificationEmail } from "./unitVerificationEmail.ts";

Deno.test("verification request links to admin review and escapes submitted content", () => {
  const email = unitVerificationEmail("owner@example.invalid", {
    app_name: "vstupenky.online", legal_name: '<img src=x onerror="alert(1)">',
    registration_number: "00006947", review_url: "https://example.invalid/organizationEdit/3",
  }, "sender@example.invalid");
  assertEquals(email.to, "owner@example.invalid");
  assertStringIncludes(email.subject, "ověření pořadatele");
  assertStringIncludes(email.html, "https://example.invalid/organizationEdit/3");
  assertStringIncludes(email.html, "&lt;img");
  assertEquals(email.html.includes("<img"), false);
  assertEquals(email.attachments.length, 0);
});
Deno.test("verification email rejects unsafe or unrelated review links", () => {
  for (const review_url of ["javascript:alert(1)", "http://example.invalid/organizationEdit/3", "https://a:b@example.invalid/organizationEdit/3", "https://example.invalid/other", "https://example.invalid/organizationEdit/3?next=bad"]) {
    assertThrows(() => unitVerificationEmail("owner@example.invalid", { review_url }, "sender@example.invalid"));
  }
});

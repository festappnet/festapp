import assert from "node:assert/strict";
import { measurementApprovalEmail } from "./measurementApprovalEmail.ts";

for (const lang of ["cs", "en"]) {
  Deno.test(`measurement request email renders ${lang} and escapes organizer content`, () => {
    const email = measurementApprovalEmail("owner@example.invalid", {
      proposed_websites: ["https://www.example.invalid", "https://example.invalid:443", "<script>alert(1)</script>"],
      lang, organization_title: "vstupenky.online", unit_id: 7,
      unit_title: '<img src=x onerror="alert(1)">', review_url: "https://example.invalid/organizationEdit/3",
    }, "sender@example.invalid");
    assert.ok(email.html.includes("https://www.example.invalid"));
    assert.ok(email.html.includes("https://example.invalid:443"));
    assert.ok(email.html.includes("&lt;script&gt;"));
    assert.equal(email.html.includes("<script>"), false);
    assert.equal(email.to, "owner@example.invalid");
    assert.equal(email.subject, lang === "en" ? "Request to enable form measurement" : "Žádost o povolení měření formulářů");
    assert.ok(email.html.includes("https://example.invalid/organizationEdit/3"));
    assert.ok(email.html.includes("&lt;img"));
    assert.ok(email.html.includes("ID: 7"));
    assert.ok(email.html.includes("vstupenky.online"));
    assert.equal(email.html.includes("<img"), false);
    assert.equal(email.attachments.length, 0);
  });
}
Deno.test("measurement request rejects unsafe or unrelated review links", () => {
  for (const review_url of ["javascript:alert(1)", "http://example.invalid/organizationEdit/3", "https://a:b@example.invalid/organizationEdit/3", "https://example.invalid/other", "https://example.invalid/organizationEdit/3?next=bad", "https://example.invalid/organizationEdit/3#bad"]) {
    assert.throws(() => measurementApprovalEmail("owner@example.invalid", { review_url }, "sender@example.invalid"));
  }
});

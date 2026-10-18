// Tests for deposit-related email translations + template branching logic.
// Run with: deno test --allow-net --allow-read supabase/functions/send-email/deposit_templates_test.ts

import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { csTranslations } from "../_shared/translations/translations.cs.ts";
import { enTranslations } from "../_shared/translations/translations.en.ts";

// =====================================================================
// csTranslations.depositPaid
// =====================================================================

Deno.test("CS depositPaid — formal, days-before deadline", () => {
  const html = csTranslations.depositPaid("500 Kč", "500 Kč", "7 dní před akcí", "formal");
  assertStringIncludes(html, "Děkujeme za úhradu zálohy");
  assertStringIncludes(html, "500 Kč"); // amount appears
  assertStringIncludes(html, "uhraďte"); // formal verb
  assertStringIncludes(html, "nejpozději"); // deadline preamble
  assertStringIncludes(html, "7 dní před akcí"); // deadline text
});

Deno.test("CS depositPaid — informal, days-before deadline", () => {
  const html = csTranslations.depositPaid("500 Kč", "500 Kč", "7 dní před akcí", "informal");
  assertStringIncludes(html, "uhraď"); // informal verb
  assertStringIncludes(html, "nejpozději");
});

Deno.test("CS depositPaid — on-site deadline collapses preamble", () => {
  const html = csTranslations.depositPaid("500 Kč", "500 Kč", "na místě", "formal");
  assertStringIncludes(html, "na místě");
  // No "nejpozději" when on-site
  assert(!html.includes("nejpozději"), "On-site variant must not include 'nejpozději' preamble");
});

// =====================================================================
// csTranslations.depositFullyPaid
// =====================================================================

Deno.test("CS depositFullyPaid — final confirmation copy", () => {
  const html = csTranslations.depositFullyPaid("1000 Kč", "formal");
  assertStringIncludes(html, "celé částky");
  assertStringIncludes(html, "1000 Kč");
  assertStringIncludes(html, "plně uhrazena");
});

// =====================================================================
// csTranslations.depositReminder
// =====================================================================

Deno.test("CS depositReminder — contains remaining + deadline + payment details", () => {
  const html = csTranslations.depositReminder(
    "500 Kč",
    "29.5.2026",
    "1234567/0100",
    "CZ50 0100 0000 0012 3456 7800",
    "VS12345",
    "formal"
  );
  assertStringIncludes(html, "Připomínáme");
  assertStringIncludes(html, "500 Kč");
  assertStringIncludes(html, "29.5.2026");
  // Payment details block
  assertStringIncludes(html.replace(/<[^>]*>/g, ""), "1234567/0100");
  assertStringIncludes(html, "VS12345");
});

Deno.test("CS depositReminder — informal tone", () => {
  const html = csTranslations.depositReminder(
    "500 Kč", "29.5.2026", "1234567/0100", null, "VS12345", "informal"
  );
  assertStringIncludes(html, "Tvá"); // informal possessive
});

// =====================================================================
// enTranslations.depositPaid / depositFullyPaid / depositReminder
// =====================================================================

Deno.test("EN depositPaid — formal, days-before deadline", () => {
  const html = enTranslations.depositPaid("CZK 500", "CZK 500", "7 days before the event", "formal");
  assertStringIncludes(html, "Thank you");
  assertStringIncludes(html, "deposit");
  assertStringIncludes(html, "CZK 500");
  assertStringIncludes(html, "7 days before the event");
});

Deno.test("EN depositFullyPaid", () => {
  const html = enTranslations.depositFullyPaid("CZK 1000", "formal");
  assertStringIncludes(html, "fully");
  assertStringIncludes(html, "CZK 1000");
});

Deno.test("EN depositReminder — contains all parts", () => {
  const html = enTranslations.depositReminder(
    "CZK 500",
    "May 29, 2026",
    "1234567/0100",
    null,
    "VS12345",
    "formal"
  );
  assertStringIncludes(html, "CZK 500");
  assertStringIncludes(html, "May 29, 2026");
  assertStringIncludes(html, "VS12345");
});

// =====================================================================
// Template selector — isFullyPaid branching logic
// =====================================================================
// The getTicketOrderPaidTemplate branches purely on amount comparison:
//   isFullyPaid = (amountPaid >= totalAmount)

function isFullyPaidPredicate(amountPaid: number, totalAmount: number): boolean {
  return amountPaid >= totalAmount;
}

Deno.test("isFullyPaid predicate — deposit only paid", () => {
  assertEquals(isFullyPaidPredicate(500, 1000), false);
});

Deno.test("isFullyPaid predicate — fully paid via amount", () => {
  assertEquals(isFullyPaidPredicate(1000, 1000), true);
});

Deno.test("isFullyPaid predicate — overpaid still fully paid", () => {
  assertEquals(isFullyPaidPredicate(1200, 1000), true);
});

Deno.test("isFullyPaid predicate — zero paid is not fully paid", () => {
  assertEquals(isFullyPaidPredicate(0, 1000), false);
});

// =====================================================================
// Deposit deadline interpretation in template
// =====================================================================
// Replicates the lookup logic in getTicketOrderPaidTemplate that translates
// the deposit feature config into a human-readable deadline string.

function depositDeadlineText(feature: any, lang: "cs" | "en"): string {
  const deadlineType = feature?.deposit_deadline;
  const deadlineDays = feature?.deposit_deadline_days;
  if (deadlineType === "on_site") {
    return lang === "cs" ? "na místě" : "on site";
  }
  if (deadlineDays) {
    return lang === "cs"
      ? `${deadlineDays} dní před akcí`
      : `${deadlineDays} days before the event`;
  }
  return lang === "cs" ? "na místě" : "on site";
}

Deno.test("Deadline interpretation — on_site → cs 'na místě'", () => {
  assertEquals(depositDeadlineText({ deposit_deadline: "on_site" }, "cs"), "na místě");
});

Deno.test("Deadline interpretation — days_before → cs '7 dní před akcí'", () => {
  assertEquals(depositDeadlineText({ deposit_deadline_days: 7 }, "cs"), "7 dní před akcí");
});

Deno.test("Deadline interpretation — days_before → en '7 days before the event'", () => {
  assertEquals(depositDeadlineText({ deposit_deadline_days: 7 }, "en"), "7 days before the event");
});

Deno.test("Deadline interpretation — missing config → on_site default (cs)", () => {
  assertEquals(depositDeadlineText({}, "cs"), "na místě");
});

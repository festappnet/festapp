import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import * as presentation from "./orderEmailPresentation.ts";
import { type Tone, translations } from "./translations/translations.ts";
import { formatCurrency } from "./utilities.ts";

// Expected fixture was captured from the five literal producer text blocks
// before extraction. Keep production wording/branch behavior stable.
export function examples(p: typeof presentation) {
  const result: Record<string, unknown> = {};
  for (const lang of ["cs", "en"] as const) {
    for (const tone of ["formal", "informal"] as Tone[]) {
      const bank = {
        account_number: "CZ0000000000000000000000",
        account_number_human_readable: "0000000000/0000",
      };
      const payment = {
        ...bank,
        amount: 800,
        paid: 0,
        deposit_amount: 300,
        currency_code: "CZK",
        variable_symbol: "20261030",
        deadline: "2026-10-30T12:00:00",
      };
      const features = [{ code: "deposit", deposit_deadline_days: 7 }];
      const key = `${lang}/${tone}/`;
      for (
        const [name, amount, deposit] of [
          ["zero", 0, 0],
          ["negative", -10, 0],
          ["unpaid", 800, 0],
          ["deposit", 800, 300],
        ] as const
      ) {
        result[key + `confirmation/${name}`] = p
          .confirmationPaymentSubstitutions(
            { ...payment, amount, deposit_amount: deposit },
            features,
            lang,
            tone,
          );
      }
      for (
        const [name, total, paid] of [
          ["zero", 0, 100],
          ["unpaid", 800, 0],
          ["underpaid", 800, 300],
          ["overpaid", 800, 900],
          ["paid", 800, 800],
        ] as const
      ) {
        result[key + `update/${name}`] = p.updateBalanceReasoning(
          total,
          paid,
          "CZK",
          bank,
          payment,
          lang,
          tone,
        );
      }
      for (const paid of [300, 800, 900]) {
        result[key + `paid/${paid}`] = p.paidPaymentSubstitutions(
          800,
          paid,
          "CZK",
          features,
          lang,
          tone,
        );
      }
      for (const timeDiff of [5 * 86400000, 0, -5 * 86400000]) {
        result[key + `reminder/${timeDiff}`] = p.reminderBalanceReasoning(
          timeDiff,
          Math.ceil(Math.abs(timeDiff) / 86400000),
          500,
          300,
          "CZK",
          bank,
          payment,
          lang,
          tone,
        );
      }
      result[key + "depositReminder/days"] = p.depositReminderBalanceReasoning(
        500,
        "CZK",
        features,
        "2026-11-06T12:00:00",
        bank,
        payment,
        lang,
        tone,
      );
      result[key + "depositReminder/site"] = p.depositReminderBalanceReasoning(
        500,
        "CZK",
        [],
        "2026-11-06T12:00:00",
        bank,
        payment,
        lang,
        tone,
      );
      result[key + "paid/site"] = p.paidPaymentSubstitutions(
        800,
        300,
        "CZK",
        [{
          code: "deposit",
          deposit_deadline: "on_site",
          deposit_deadline_days: 7,
        }],
        lang,
        tone,
      );
    }
  }
  return result;
}

Deno.test("payment presentation retains exact pre-extraction producer output", async () => {
  const expected = JSON.parse(
    await Deno.readTextFile(
      new URL("./testdata/orderEmailPresentation.json", import.meta.url),
    ),
  );
  assertEquals(examples(presentation), expected);
});

Deno.test("zero and deposit confirmation use canonical text and total scalar", () => {
  const payment = {
    amount: 800,
    currency_code: "CZK",
    deposit_amount: 300,
    account_number: "CZ0000000000000000000000",
    account_number_human_readable: "0000000000/0000",
    variable_symbol: "20261030",
  };
  for (const lang of ["cs", "en"] as const) {
    for (const tone of ["formal", "informal"] as Tone[]) {
      const zero = presentation.confirmationPaymentSubstitutions(
        { ...payment, amount: 0 },
        [],
        lang,
        tone,
      );
      assertEquals(
        zero.balanceReasoning,
        translations[lang].zeroOrder("CZK", tone),
      );
      assertEquals(zero.amount, formatCurrency(0));
      const deposit = presentation.confirmationPaymentSubstitutions(
        payment,
        [],
        lang,
        tone,
      );
      assertEquals(deposit.amount, formatCurrency(800));
      assertStringIncludes(deposit.balanceReasoning, formatCurrency(300));
      assertStringIncludes(deposit.balanceReasoning, formatCurrency(500));
      assertEquals(
        presentation.paidPaymentSubstitutions(800, 300, "CZK", [], lang, tone)
          .amount,
        formatCurrency(300),
      );
    }
  }
});

Deno.test("generated confirmation examples retain canonical zero text and deposit total", async () => {
  const asset = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../../../assets/email_templates/preview_examples.json",
        import.meta.url,
      ),
    ),
  );
  const confirmations = asset.records.filter((r: any) =>
    r.templateCode === "TICKET_ORDER_CONFIRMATION"
  );
  assertEquals(confirmations.length, 12);
  for (const record of confirmations) {
    if (record.scenario === "zero") {
      const tr = translations[record.locale as keyof typeof translations];
      assertEquals(
        record.values.balanceReasoning,
        tr.zeroOrder("CZK", record.tone),
      );
      assertEquals(record.values.amount, formatCurrency(0));
    } else {
      assertEquals(record.values.amount, formatCurrency(800));
    }
  }
});

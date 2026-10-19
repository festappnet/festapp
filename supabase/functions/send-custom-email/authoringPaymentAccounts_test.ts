import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  authoringPaymentAccounts,
  type LinkedAuthoringAccount,
} from "./authoringPaymentAccounts.ts";

function account(
  id: number,
  priority: number,
  currencies = ["CZK"],
  type = "FIO",
): LinkedAuthoringAccount {
  return {
    priority,
    bank_accounts: {
      id,
      type,
      account_number: "CZ6508000000192000145399",
      account_number_human_readable: `${id}/0800`,
      supported_currencies: currencies,
    },
  };
}

Deno.test("configured form accounts lead, with deterministic unit currency fallbacks and deduplication", () => {
  const examples = authoringPaymentAccounts([
    account(4, 4),
    account(2, 0),
    account(3, 3, ["EUR"]),
    account(2, 0),
  ], [3, 999]);
  assertEquals(examples.map((value) => value.accountNumber), [
    "3/0800",
    "2/0800",
    "4/0800",
  ]);
  assertEquals(examples[0].currencies, ["EUR"]);
  assertEquals(examples[1].currencies, ["CZK"]);
  assertEquals(examples[0].iban, "CZ65 0800 0000 1920 0014 5399");
});

Deno.test("unit examples exclude cash, unlinked form IDs and empty account identities", () => {
  const empty = account(8, 0);
  empty.bank_accounts.account_number = null;
  empty.bank_accounts.account_number_human_readable = null;
  assertEquals(
    authoringPaymentAccounts([account(1, 0, ["CZK"], "CASH"), empty], [1, 999]),
    [],
  );
  assertEquals(
    authoringPaymentAccounts([account(3, 1), account(2, 1)], []).map((value) =>
      value.accountNumber
    ),
    ["2/0800", "3/0800"],
  );
});

Deno.test("missing display metadata is not replaced by invented account or currency values", () => {
  const domestic = account(2, 0);
  domestic.bank_accounts.account_number = null;
  domestic.bank_accounts.supported_currencies = null;
  assertEquals(authoringPaymentAccounts([domestic], []), [{
    accountNumber: "2/0800",
    iban: "",
    currencies: [],
  }]);
});

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  authoringPaymentAccounts,
  loadAuthoringPaymentAccounts,
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

Deno.test("bank examples use public RPC through the actual Supabase transport", async () => {
  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2.58.0");
  const requests: Request[] = [];
  const client = createClient("https://backend.test.invalid", "service-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const req = new Request(input, init);
      requests.push(req);
      return Response.json({ linkedAccounts: [account(1, 0, ["CZK"])], formAccountIds: [1] });
    } },
  });
  const result = await loadAuthoringPaymentAccounts(client, { unit: 8, occasion: 42, organization: 3 });
  assertEquals(result.length, 1);
  assertEquals(requests.length, 1);
  assertEquals(new URL(requests[0].url).pathname, "/rest/v1/rpc/get_email_authoring_payment_accounts");
  assertEquals(requests[0].headers.get("content-profile"), "public");
  assertEquals(await requests[0].json(), { p_unit_id: 8, p_occasion_id: 42 });
});
Deno.test("unit-only bank examples pass no invented occasion and reject unavailable metadata", async () => {
  let args: unknown;
  const client = { rpc: async (_: string, value: unknown) => {
    args = value;
    return { data: { linkedAccounts: [], formAccountIds: [] }, error: null };
  } };
  assertEquals(await loadAuthoringPaymentAccounts(client, { unit: 8, organization: 3 }), []);
  assertEquals(args, { p_unit_id: 8, p_occasion_id: null });
  let failed = false;
  try { await loadAuthoringPaymentAccounts({ rpc: async () => ({ data: null, error: { code: "PGRST202" } }) }, { unit: 8 }); }
  catch (_) { failed = true; }
  assertEquals(failed, true);
});

import { formatIBAN } from "../_shared/utilities.ts";

export interface AuthoringPaymentAccount {
  accountNumber: string;
  iban: string;
  currencies: string[];
}

export interface LinkedAuthoringAccount {
  priority: number;
  bank_accounts: {
    id: number;
    type: string;
    account_number: string | null;
    account_number_human_readable: string | null;
    supported_currencies: string[] | null;
  };
}

/** Display examples only: the actual order's payment account is never queried. */
export function authoringPaymentAccounts(
  linked: LinkedAuthoringAccount[],
  formAccountIds: number[],
): AuthoringPaymentAccount[] {
  const eligible = linked.filter(({ bank_accounts: account }) =>
    account.type !== "CASH" &&
    (account.account_number?.trim() ||
      account.account_number_human_readable?.trim())
  ).sort((a, b) =>
    a.priority - b.priority || a.bank_accounts.id - b.bank_accounts.id
  );
  const configured = eligible.filter(({ bank_accounts: account }) =>
    formAccountIds.includes(account.id)
  );
  const seen = new Set<number>();
  return [...configured, ...eligible].filter(({ bank_accounts: account }) => {
    if (seen.has(account.id)) return false;
    seen.add(account.id);
    return true;
  }).map(({ bank_accounts: account }) => ({
    accountNumber: account.account_number_human_readable?.trim() ||
      account.account_number?.trim() || "",
    iban: formatIBAN(account.account_number?.trim()),
    currencies: [...new Set(account.supported_currencies ?? [])].sort(),
  }));
}

/** The private eshop schema is deliberately not exposed through PostgREST. */
export async function loadAuthoringPaymentAccounts(
  client: { rpc: (name: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: unknown }> },
  context: Record<string, number>,
): Promise<AuthoringPaymentAccount[]> {
  const { data, error } = await client.rpc("get_email_authoring_payment_accounts", {
    p_unit_id: context.unit,
    p_occasion_id: context.occasion ?? null,
  });
  if (error) throw error;
  if (!Array.isArray(data?.linkedAccounts) || !Array.isArray(data?.formAccountIds)) {
    throw new Error("Payment example metadata unavailable");
  }
  return authoringPaymentAccounts(data.linkedAccounts, data.formAccountIds);
}

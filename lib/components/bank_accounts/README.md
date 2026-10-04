# Bank Accounts

## Architecture (Non-Obvious)

Accounts (`eshop.bank_accounts`) link to units via many-to-many (`eshop.unit_bank_accounts`). A single account can serve multiple units. Priority is scoped to the link, not the account.

## Dual Security Model

- **Unit Context** (Unit Manager): Link/unlink accounts, reorder priority. Check: `check_is_manager_on_unit(unit_id)`.
- **Account Context** (Bank Account Admin): Edit IBAN, tokens, manage access. Check: `eshop.bank_account_users` table.

Creating a new account auto-grants Bank Account Admin rights to the creator.

## Gotchas

- **Unlink != Delete**: "Delete" in Unit UI only unlinks. Account persists for other units/history.
- **Currency Routing**: Sorted by priority ASC. First account matching a currency = Primary (green badge), rest = Backup (gray).
- **Two account number fields**: `account_number_human_readable` for invoices/UI, `account_number` for matching/API calls.
- **Secrets**: API tokens in `eshop.secrets`. Frontend only sees masked last 4 chars. Write-only via `update_bank_account_token`.
- **Priority reorder**: Triggers batch update of ALL link items with new indices.

## Schema

- `eshop.bank_accounts` -- core entity (IBAN, Title, Type)
- `eshop.unit_bank_accounts` -- link table (Unit ID, Account ID, Priority)
- `eshop.bank_account_users` -- permissions (User ID, Account ID, `is_admin`, `is_support`)
- `eshop.secrets` -- secure token storage


## Canonical token updates and activation errors

For a BankSync account, “Update token” calls `bank-sync-manage` -> tenant-scoped
BankSync `PUT /bank-accounts/:id/fio-token`. The operation verifies the full
stored token digest before reporting storage success. Legacy SQL token updates
are blocked after cutover; deploying the backend requires deploying the selected
tenant client as well. Never claim end-to-end cutover from a backend deploy alone.

Fio token creation is not authorization: the user must authorize it in Fio
Internetbanking (Settings -> API), then allow up to five minutes for activation.
On 2026-10-04 an unauthorized token returned HTTP 500 after 30.4 seconds, which
an earlier 20-second client timeout hid. Fio documents 500 as nonexistent/inactive
token: https://www.fio.cz/docs/cz/API_Bankovnictvi.pdf (section 8).
`fio_token_invalid_or_inactive` is a stable error code, not a raw bank response.
The UI distinguishes token storage success from bank verification failure.
Polling stays enabled so authorization later recovers without re-uploading.
Account settings refresh BankSync status and clear stale errors after a successful
bank pull. A transport timeout or proxy 500 must never be called an invalid token.

### Account details and bank identity

Updating a connected account commits its Festapp details and a durable `update_details` intent in one SQL transaction. The client immediately flushes the intent through `bank-sync-manage`; `bank-sync-reconcile` retries interrupted or failed delivery. BankSync receives the current account label and storage is read back before completion. Beneficiary name, display account formatting and accepted currencies remain Festapp payment-instruction fields, not duplicated BankSync configuration. The existing account-operation fence prevents overlap with credential rotation.

Connected physical account identity remains immutable: add/select a new account for future orders rather than reassigning historical bank transactions. Creation and token/email setup are separate operations; API ingestion currently supports Fio. BankSync's public API supports Fio and Air Bank adapters, not arbitrary bank API providers.

A bank cooldown or transient failure after the full persisted-token digest check is a deferred verification, not failed storage. Complete the saved-token operation, re-enable polling and show `token_saved: true` with the verification error. Leaving it uncertain and polling disabled falsely reported failure on a normal concurrent poll.

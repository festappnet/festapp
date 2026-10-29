# Bank Accounts

## Architecture (Non-Obvious)

Accounts (`eshop.bank_accounts`) link to units via many-to-many (`eshop.unit_bank_accounts`). A single account can serve multiple units. Priority is scoped to the link, not the account.

## Dual Security Model

- **Unit Context** (Unit Manager): Link/unlink accounts, reorder priority. Check: `check_is_manager_on_unit(unit_id)`.
- **Account Context**: Edit IBAN, tokens, transactions and access only when the caller is both Bank Account Admin and Unit Manager of a unit actually linked to the account. `can_manage_bank_account` owns this conjunction; the direct connection route and BankSync RPCs use the same policy. Account membership alone does not grant management.

Creating a new account in a unit requires Unit Manager and auto-grants Bank Account Admin to the creator. Linking an existing account requires Unit Manager of the target unit plus Bank Account Admin. Reordering/unlinking an existing unit link requires Unit Manager; these operations do not change account details or credentials.

Here the UI term "správce organizace" denotes `unit_users.is_manager`. Tenant-wide `organization_users.is_admin` is a separate role and does not substitute for either bank requirement. Shared physical accounts can serve multiple units: a managed unit must be actually linked, never inferred from a supplied ID. Revoking its manager role removes account-management capabilities on the next context load and is checked live by every account mutation.

## Gotchas

- **Unlink != Delete**: "Delete" in Unit UI only unlinks. Account persists for other units/history.
- **Currency Routing**: Sorted by priority ASC. First account matching a currency = Primary (green badge), rest = Backup (gray).
- **Two account number fields**: `account_number_human_readable` for invoices/UI, `account_number` for matching/API calls.
- **Tokens**: BankSync owns encrypted bank credentials. Updates use `bank-sync-manage`, with digest readback and durable recovery; Festapp exposes only a masked hint.
- **Priority reorder**: Triggers batch update of ALL link items with new indices.

## Schema

- `eshop.bank_accounts` -- core entity (IBAN, Title, Type)
- `eshop.unit_bank_accounts` -- link table (Unit ID, Account ID, Priority)
- `eshop.bank_account_users` -- permissions (User ID, Account ID, `is_admin`, `is_support`)
- Historical `eshop.secrets` rows are retired credentials; no live bank path reads or writes them.


## Canonical token updates and activation errors

For a BankSync account, “Update token” calls `bank-sync-manage` -> tenant-scoped
BankSync `PUT /bank-accounts/:id/fio-token`. The operation verifies the full
stored token digest before reporting storage success. Legacy SQL token update RPCs
are removed after cutover; deploying the backend requires deploying the selected
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

Connected physical account identity remains immutable: add/select a new account for future orders rather than reassigning historical bank transactions. Creation and token/email setup are separate operations; API ingestion currently supports Fio. BankSync 0.5.0 supports email notifications from Fio, Air Bank, ČSOB, MONETA, CREDITAS, Raiffeisenbank, UniCredit and Česká spořitelna. The bank code in the receiving account selects the provider; the historical account type does not determine support. The shared Dart capability map, SQL provider resolver/constraint and Edge management gate mirror BankSync's exported bank catalog. API synchronization remains Fio-only.

A bank cooldown or transient failure after the full persisted-token digest check is a deferred verification, not failed storage. Complete the saved-token operation, re-enable polling and show `token_saved: true` with the verification error. Leaving it uncertain and polling disabled falsely reported failure on a normal concurrent poll.

## Synchronization control and health

Account admins can pause/resume automatic synchronization without replacing the
token. The connection status, order payment warnings and form/unit bank cards
share the server-owned `bank_sync_warning` diagnosis. Form bank choices omit
`bank_sync` connection details even for connected accounts. Missing details or
an unknown state must never create a warning or claim a healthy connection;
only an explicit connected state can show the positive status. See
[health and incident notifications](../../../docs/operations/banksync/HEALTH-ALERTS.md).

## Local payment-reference reservations

Festapp owns reference issuance independently of BankSync ingestion. Activated
scopes use the private SQL registry in `eshop_payment_references/` in the existing
order transaction. Account aliases share canonical receiving identity; committed
symbols and form watermarks survive order deletion. Enrollment freezes receiving
identity and starts locked. See the [scope/import/activation runbook](../../../docs/operations/banksync/FESTAPP-PAYMENT-REFERENCES-2026-10-18.md).

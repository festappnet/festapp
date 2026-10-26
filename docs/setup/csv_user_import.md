# CSV user import

Occasion managers, organization administrators and unit editors can import
participants from the Users administration using the CSV
import dialog. The first row is a header; column order does not matter. The
dialog's **Expected file format** section lists and copies the currently
supported headers.

The required columns are:

- `E-mailová adresa`
- `Jméno:`
- `Příjmení:`

A delivery mailbox can belong to several participants. The client keeps every
row and assigns deterministic collision-free `+N` sign-in aliases when needed.
It preserves the original mailbox as `email_delivery`. Reimport reconciliation
matches delivery mailbox, name and surname against existing occasion users, then
reuses their canonical sign-in email and UUID. Reordering rows or importing only
one member of a shared mailbox must not overwrite another person.

Two rows with the same normalized mailbox, name and surname are ambiguous and
rejected. The current CSV format has no stable-ID column; resolve ambiguous
identities before import. Names changing on a shared mailbox can also require
manual identity review instead of assuming the same email denotes the same person.

## Update semantics and transaction

The import is a patch, not a replacement:

- An omitted optional column leaves its existing value unchanged.
- A parsed key updates its value. Blank sex (`Jsi:`) and birth-date cells are
  omitted by the CSV parser and preserve existing values. Non-empty dates use
  the strict `d.M.y` format.
- For service columns, an explicitly empty cell clears only that service family.
- Accommodation and food are independent service families. Importing one never
  removes the other.
- CSV import never changes roles or editor/manager/cleaning permissions.

The client sends one confirmed batch to
`import_profiles_client_sync_v1` when Client Sync v1 is selected; the legacy
adapter calls `public.import_occasion_users_from_csv`. Both delegate the row
semantics to the CSV SQL module. That module validates and
executes user creation or assignment, field patches, group changes, and
deletions in one PostgreSQL transaction. Any invalid row rolls back the entire
batch. Imports for the same occasion are serialized with a transaction-level
advisory lock, so two concurrent imports cannot interleave.

The RPC accepts rows shaped as follows:

```json
{
  "user_id": "optional existing UUID",
  "email_delivery": "original-mailbox@example.com",
  "data": { "email": "person@example.com", "name": "..." },
  "services": { "accommodation": { "room-a": "paid" } },
  "group_title": "optional authoritative standard group"
}
```

Only keys present in `data`, `services`, and the outer row are authoritative.
This presence-based contract is the canonical seam for CSV imports; callers
must not upsert `occasion_users` directly.

This behavior intentionally lives at the CSV RPC boundary rather than in a
table trigger. A global merge trigger cannot distinguish an omitted import
field from an intentional key removal by another workflow. Older clients must
therefore be upgraded before using the patch-based CSV import; direct
`occasion_users` upserts are not a supported import contract.

## Group column

`Skupina:` is optional. `Skupina` without the colon is accepted as well.
When the column is present, its value is authoritative for the participant's
standard group on the current occasion:

- A non-empty value assigns the participant to the named group.
- A missing group is created automatically.
- Reimporting the participant with another value removes the previous standard
  group membership and moves the participant to the new group.
- An empty value removes the participant from their standard group.
- Omitting the entire `Skupina:` column leaves existing membership unchanged.

An imported participant can belong to only one standard group. Typed groups,
such as game groups, are not changed by the CSV import. Group synchronization
is part of the same bulk-import transaction, so a failed group change does not
leave any other row in the batch half-updated.

## Example

```csv
E-mailová adresa,Jméno:,Příjmení:,Poznámka:,Skupina:
bujnmi@gmail.com,Bujn,Mi,Imported from CSV,Testovací skupina CSV
```

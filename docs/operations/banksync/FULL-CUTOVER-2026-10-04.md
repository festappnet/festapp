# Complete Festapp bank ingress cutover

The authorized scope is every Festapp bank-import path on the canonical backend.
Only the selected `prod/festapptickets` web client is released; no other tenant
build is implied. The user confirmed the former bank-email addresses are unused.

BankSync owns Fio credentials, polling, recovery windows, authenticated bank email
intake and signed deliveries. Festapp owns bank/account permissions, immutable
physical mappings, the ledger, order matching and the global ticket-email queue.
`fetch-transactions` stays as the authenticated occasion-editor API used by
existing clients; it only delegates to BankSync. It contains no bank adapter.

## Invariants and retirement

Activation locks the account and adopts existing Fio movement identities. A replay
compares the original bank facts, never re-credits history or undoes a manual
unpair. Conflicting facts are quarantined. Existing amounts, dates and pairings
are not rewritten. New tokens resume expired/suspended ingestion only after the
stored full credential digest is verified. Account provider is resolved from the
physical bank identity, including historically generic Fio/Air Bank rows.

Delete the two old Fio implementations, old bank-email parser and tests, legacy
bank credential/ingest/pairing RPCs, and their scheduler/bootstrap registrations.
Historical applied migrations, import provenance and audit rows remain history;
they are not runnable fallback implementations. The canonical schema retains old
response columns for client shape compatibility but no bank credential reader.
New accounts no longer generate legacy email recipients or enable old polling.

## Ordered rollout

1. Apply `20261004203000_bank_sync_full_cutover_prepare.sql` atomically with its
   migration digest ledger, preserving the old worker until each account moves.
2. Run `automation/banksync/cutover_fio_accounts.py` with reviewed explicit account
   IDs and an external protected operator/evidence directory. It creates paused
   owner-scoped remote accounts, verifies copied credential digests, commits the
   mapping/identity barrier, then enables polling only for unexpired accounts.
   Re-running resumes the same physical mapping; credentials never enter logs.
3. Prove fresh bank pulls and receipts for all five active API accounts (2, 4,
   1023, 1024, 1025). Expired accounts (1, 3, 5, 6, 737) move suspended. Other
   dormant/test/manual/cash accounts do not become active merely due to migration.
4. Unschedule only the retired bank polling cron in the scheduler database.
   Apply `20261004204000_retire_legacy_bank_ingress.sql`; its guard rejects an
   unmigrated active Fio account with an unexpired credential.
5. Install the clean-main Function bundle and matching writer policy; the
   directory replacement removes retired handlers. Deploy the selected client.
6. Verify removed functions/routes/jobs, active BankSync polling, receipt outcomes,
   historical ledger preservation, and the live web version.

## Bank email remains supported by BankSync

Retiring Festapp's unused SNS parser does not remove BankSync email support.
New setup uses the server-issued `@banksync.festapp.net` recipient and encrypted
authenticated email spool. Fio/Air Bank observations with unproven movement
identity are retained for inspection, not automatically credited by Festapp.
A real provider evidence/identity rollout remains necessary before claiming
fully automatic email payment confirmation. No test fixture is production proof.

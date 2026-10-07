# Ticketing email template visibility

Extended the existing IS_APP_SUPPORTED organization filter to hide APP_LINKS, ACCOUNT_DELETION_CONFIRM and ACCOUNT_DELETION_COMPLETE alongside the two existing auth templates. No template data or delivery code changed.

Template contract and tenant-scope SQL tests passed in a disposable local database; full-app visibility and retained ticket/custom templates verified. The disposable database was removed.

Live body differed from repository formatting, schema qualification and equivalent empty-result coalescing only; inspected before replacement. Migration 20261006204500 committed atomically with ledger and schema notification from PR #331. SHA256 ce7a2f8f46cbb5f08dcfec343f2676164f899d9e978fecb5afa71ff821bcbd64. Backup/evidence retained at /var/lib/festapp-rehearsal-evidence/template-visibility-20261006.

Canonical host/database and organization 3 IS_APP_SUPPORTED=false verified. Read-only live verification confirmed all three app templates absent and ticket order confirmation retained. No additional web build required.

# Organization Google sign-in setting - 2026-10-02

Approved frontend rollout: prod/festapptickets, https://vstupenky.online,
organization 3. Shared main contains the organization-admin setting. No other
tenant frontend or native application is deployed by this rollout.

Organization settings now expose "Povolit přihlášení přes Google" next to the
registration setting. Registration remains independent: disabling registration
does not prevent existing users from signing in or linking an existing account.
Disabling Google prevents subsequent broker transitions and preserves identities.

The admin RPC validates a boolean setting and updates the organization and client
availability atomically. Only operator-provisioned clients can become enabled;
organization administrators cannot activate unfinished/native clients. Existing
enabled clients and organization preferences were preserved by the migration.

PR: https://github.com/festappnet/festapp/pull/218
Main base: c06f171ac3fc948f37ead8919040f82504ccdd39
Production SHA: ceef69a8cd13eb7cbf58c6c5aabefc2b952de060
Version: 0.20.53+537
Deployment: https://github.com/festappnet/festapp/actions/runs/37003537593

Applied migration: supabase/migrations/20261002170000_organization_google_login_setting.sql
SHA256: 39bcc015b2ceba4c0c1f54abaa6bb9e70525dc9af8c0439ca8b1d3d01bdc2388
Database: festapp_rehearsal_20260909220601
The reviewed Access SQL helper checked the target database and exact file digest.
The migration ledger and production readback confirm the migration is installed.
Organizations 1 and 3 retain Google and registration enabled; exactly their four
web/flutter-web clients are enabled and provisioned. No native client is enabled.

Validation: full Google broker and organization-setting SQL regressions passed
inside a rolled-back transaction. Tests cover admin permission, tenant isolation,
boolean validation, registration independence and unprovisioned clients. Flutter
model and Google-panel tests passed; targeted analysis has no errors or warnings.
The tenant drift gate passed against current main. Unrelated workspace changes
were preserved. No production accounts were changed solely for testing.

Frontend deployment succeeded. Three consecutive independent production probes
confirmed version 0.20.53+537, the immutable Flutter bundle, matching service
worker generation, canonical Cloudflare runtime and legal routes. Post-migration
public capability probes confirm Google remains enabled for organizations 3 and
1. Full real-account Google sign-in was not performed solely for verification.

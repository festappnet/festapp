# vstupenky.online Google sign-in rollout - 2026-10-02

Approved scope: prod/festapptickets, https://vstupenky.online, organization 3.
Canonical activation document confirms festapptickets / canonical / generation 1.
Database preflight confirms festapp_rehearsal_20260909220601, organization 3
APP_NAME vstupenky.online, DEFAULT_URL https://vstupenky.online and registration
enabled. The Google broker migration 20261001150000 is installed. Before this
rollout, only the two live.festapp.net clients were enabled.

Google login already exists in the shared web client and Flutter source. Reuse
the installed server-side Google OAuth client and its api.festapp.net callback;
no separate project, client secret or direct Google JavaScript SDK is required.
Provision exact web and flutter-web clients for vstupenky.online, with /google-auth
and /app/google-auth return routes. Do not provision native clients or wildcards.

Reviewed registry activation SQL:
vstupenky-google-activation-2026-10-02.sql. Target/organization/URL guards and
post-insert assertions run in one transaction. A rolled-back rehearsal succeeded
and returned no enabled organization-3 rows afterward.

Shared UI fix: web account-proof email now uses the provider email as a default,
keeps manual edits through error renders and clears the draft for a new attempt.
The proof-email regression failed before the change; nine targeted web modal,
Google service and callback-hosting tests passed.

PR: https://github.com/festappnet/festapp/pull/217
Main base: a9d5d328eeb5db045910ab10f146fa1646707ce4
Production SHA: 0508e45b0e9e07e0a2d9f60a290996163662fd50
Version: 0.20.52+536
Deployment: https://github.com/festappnet/festapp/actions/runs/37001421138
Tenant drift passed. Production incorporates the recent merged ticket changes,
including PR 216. Original workspace changes were preserved.

Production readback passed three consecutive deployment probes. Registry activation
was committed after deployment verification. Both organization-3 web clients are
available; wrong organizations, wrong origins and unprovisioned native clients are
rejected. Original live.festapp.net clients remain available.

An isolated browser verified the Google button, navigation to Google's account
selection and recovery after cancellation. No real production account
registration, linking, unlinking or logout was performed solely for verification.

The organization-setting follow-up supersedes this frontend release. See
organization-google-login-setting-2026-10-02.md for its migration and deployment
receipt. The activation SQL above is historical and must not be rerun unchanged
against the newer provisioned-client schema.

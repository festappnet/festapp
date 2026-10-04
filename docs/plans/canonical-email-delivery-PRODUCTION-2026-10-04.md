# Canonical email production activation - 2026-10-04

Backend is ACTIVE and all eleven approved frontend deployments succeeded. The public production origins independently report version 0.20.83+567. Orders email status, tooltip and scoped history are included in that release.

## Production authority

- Account/region: AWS 274371802740 / eu-central-1. Verified production access and sending enabled; live account quota read 50,000/day and 14/second. Festapp allocation: 2/second and 10,000/day, with the canonical safety reserve; other senders were untouched.
- Frontend source main: 6835e2223cb7206d34e5b07647afc0be9c147475; final backend recovery source: ef75f3d94592774249a671c562046bb45f0331a8. PRs #266, #267, #268 and #269 were independently reviewed and merged through the existing owner-admin exemption; branch protection was not changed.
- Protected target: festapp-supabase-rehearsal-01 / festapp_rehearsal_20260909220601. The hostname/database historical names do not mean this is a disposable test environment.
- Canonical cutover 20261003200000 and incremental runtime guard migration 20261004020000 and idle quota recovery migration 20261004021000 are applied with their migration-ledger records in the same transactions.
- Function bundle source: 03639199f8e0fafea6d8a217940e2439418085f9. Gateway digest: festapp-email-gateway@sha256:503d8a82a281899303d9e170ff220a2ef059cefa906785c1ccfa4e705ee55640, ARM64. Function/gateway source is unchanged between its reviewed build commit and final runtime source main.
- Signed GoTrue email hook enabled on https://api.festapp.net/functions/v1/auth-email-hook; SMTP host/user/password disabled. Auth health is HTTP 200. Gateway is private: public route returns 404, and only its container receives SES API credentials.
- Recovery cron job 12 is active in the default postgres control plane, targeting the canonical runtime database and executing SELECT public.recover_email_delivery(). Recent runs succeeded. Unrelated jobs were preserved.
- email_capacity.paused=false. Live quota refresh through the actual private gateway returned HTTP 200. Live health had no alerts, unmatched feedback, post-action backlog, provider outage or wake incident.

## Real delivery evidence

Both required pre-deployment mails to bujnmi@gmail.com were sent using the actual SES gateway with isolated queue state. The user confirmed both arrived and the attached PDF opened.

The production activation canary to the same owner address has canonical message ID bda86db0-8006-4648-b867-a53b0110b3c2 and provider ID 010701a10490efbb-81c99204-15e3-4e1d-9e95-68ff4f96706d-000000. SES acceptance was recorded at 2026-10-04T01:39:29.97886Z; signed provider delivery was recorded at 2026-10-04T01:39:30.708Z. The send and delivery events persisted in the production journal, and its post-action completed. No acceptance was relabeled as delivery without provider evidence.

HTTPS SNS subscription is confirmed: arn:aws:sns:eu-central-1:274371802740:festapp-canonical-email-feedback-FeedbackTopic-EmHzSOHhMArD:cf090091-eaaa-40b6-a592-2dff6adaae5e. The owner alarm subscription for bujnmi@gmail.com is confirmed on festapp-email-operations. Temporary predeployment SQS/subscription were removed after production feedback was proven.

## Rehearsal and production findings

The previously reported complete targeted suite results remain valid: 106 SQL suites, 239 Deno tests, 1052 Flutter tests, 212 web tests and 179 automation tests passed, with documented skips. The ARM64 dependency graph imported offline on the actual server. No capacity/load test or synthetic send batch was performed.

The first live migration encountered one historical paid order with an invalid/blank address. It rolled back completely, left its ledger entry absent and all 34 old queue records intact; old services were promptly restarted. PR #267 added invalid-address legacy fixtures (blank, malformed and JSON null) and preserves these candidates as unknown with their original recipient and explicit reconciliation error. The disposable cutover and five targeted email SQL suites passed.

Production safeupdate additionally rejected singleton updates lacking WHERE, and pinned GoTrue rejected the internal non-loopback HTTP hook URL. PR #268 adds WHERE singleton without disabling the database guard and uses the configured public HTTPS hook origin. Its incremental migration and five targeted email SQL suites passed, and actual live quota refresh/Auth health subsequently succeeded. PR #269 also keeps quota fresh while the queue is idle through the same paused-gated, transaction-coalesced recovery wake. Its rolled-back functional test and nine runtime/schema automation tests passed. Actual production recovery refreshed quota and heartbeat at 2026-10-04T01:51:32Z without sending another message.

The successful migration retained 33 future pending old messages and two unknown records: one ambiguous old send and the invalid historical paid candidate. Unknown records require individual audited reconciliation; they were not automatically resent, discarded or assigned invented delivery evidence. Existing public adapters and legacy audit remain available.

Protected pre-cutover database dump, runtime archive, archive catalog proof, digests and operation logs are on the host under /var/lib/festapp-rehearsal-evidence/canonical-email-19556d3d6734, mode 0700 with sensitive files mode 0600. The dump catalog was checked; this report does not claim a new full restore rehearsal. After new production writes, prefer forward fixes and do not restore this backup over new orders.

## Approved web rollout

All eleven active tenant branches are approved for this rollout. Each overlays the exact runtime source main, passed the main-owned tenant drift checker and uses version 0.20.83+567. No inactive tenant branch or native store release is included.

| Tenant | Origin | Commit | Deployment |
|---|---|---|---|
| festapp | https://live.festapp.net | 58682688d7d3 | [success](https://github.com/festappnet/festapp/actions/runs/37168681439) + live version verified |
| festapptickets | https://vstupenky.online | ed2072f77e17 | [success](https://github.com/festappnet/festapp/actions/runs/37168682885) + live version verified |
| hvezdamorska | https://hvezdamorska.festapp.net | 23c0ba75732a | [success](https://github.com/festappnet/festapp/actions/runs/37168684649) + live version verified |
| absolventskyvelehrad | https://app.absolventskyvelehrad.cz | 56788f4e6218 | [success](https://github.com/festappnet/festapp/actions/runs/37168730031) + live version verified |
| aksmcz | https://csa2024.festapp.net | 3e50a324897c | [success](https://github.com/festappnet/festapp/actions/runs/37168732155) + live version verified |
| cavfotofest | https://clovekavira.festapp.net | c7f0d986a8aa | [success](https://github.com/festappnet/festapp/actions/runs/37168733708) + live version verified |
| csmostrava2026 | https://csmostrava.festapp.net | 8b4916bce91c | [success](https://github.com/festappnet/festapp/actions/runs/37168735444) + live version verified |
| doobiscup | https://biscup.festapp.net | bbd1566f3162 | [success](https://github.com/festappnet/festapp/actions/runs/37168737229) + live version verified |
| farnostopava | https://farnostopava.festapp.net | 3d8cb8d673d2 | [success](https://github.com/festappnet/festapp/actions/runs/37168738824) + live version verified |
| festivalslunovrat | https://slunovrat.festapp.net | 0538ec5b958a | [success](https://github.com/festappnet/festapp/actions/runs/37168740980) + live version verified |
| jubileum2025 | https://jubileum2025.festapp.net | a41e72fa9224 | [success](https://github.com/festappnet/festapp/actions/runs/37168743028) + live version verified |

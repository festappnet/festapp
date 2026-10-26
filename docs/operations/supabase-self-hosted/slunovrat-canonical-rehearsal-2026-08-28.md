# Slunovrat canonical rehearsal — 2026-08-28

The legacy `slunovratopava` Supabase project is PostgreSQL 15.1 and has no
trustworthy migration ledger. It was therefore treated only as a read-only
source. No canonical migration was replayed against the cloud project.

The encrypted snapshot was restored into isolated raw and managed staging and
merged forward into `festapp_rehearsal_20260828234500`, the PostgreSQL 17
canonical target already containing the validated `default` and `a` sources.
The run is now `validated` with zero non-pass gates:

- 2,455 source Auth users; 2,450 inserted and five approved identity mappings;
- canonical password hashes unchanged and old merged sessions deliberately not
  imported, requiring ordinary reauthentication for those five accounts;
- 254 Storage metadata objects and 689,596,476 physical bytes copied and
  independently rehashed; total canonical Storage is 1,453 objects /
  1,211,456,042 bytes;
- five mapped occasions and 30 source-scoped public client-sync scopes;
- 91 legacy rows preserved privately: five merged profiles, 81 ambiguous
  companion relationships, three duplicate normalized profile e-mails and two
  rows from a removed old e-mail-template table;
- no previous-source client scope, aggregate version, metadata row or password
  hash changed; no row or file was deleted and no production R2 write occurred.

The public rehearsal endpoint returned `Slunovrat 2026` at mapped occasion ID
`1072557` with exactly 132 events; Auth and Storage health returned HTTP 200.
All 228 remaining legacy Supabase Storage URLs have a copied object. Rewriting
their host, production DNS/write authority, and client release activation remain
separate final-cutover gates.

## Legacy-client compatibility audit — 2026-08-29

The encrypted source snapshot contains 219 distinct public function names. The
archived Slunovrat client referenced 56 RPC names and 55 are present in that
snapshot; its occasion-settings writer already referenced the absent
`update_occasion_203`, so the old cloud is not a trustworthy target for further
schema evolution.

The current shared client references 54 RPC names not present in the source
snapshot. Most belong to disabled modules or to the newer administration
surface (speakers/counseling, Client Sync activity, the atomic event/map
editors, reception, cleaning, feedback and entity-level e-mail templates). The
enabled public Slunovrat flow was exercised on the Cloudflare staging build:
startup, program, event detail/description, browser back, map, news, information
and login all completed against the legacy source. `get_speakers` is an
intentional optional read for pre-speaker tenants and returns an empty bundle
only for the exact missing-function response.

`set_saved_program` was the one newly reachable public write missing from the
legacy source. The transition client now keeps a narrow compatibility adapter:
it attempts the RPC first and, only for PostgREST `PGRST202`, performs the old
RLS-protected single-event join/remove followed by an authoritative readback.
Permission, connectivity and server errors are not hidden, and non-atomic bulk
replacement is rejected. Its removal condition is activation of the canonical
`set_saved_program_client_sync_v1` path for every tenant.

This does not certify the complete modern administration UI against the old
cloud. That surface is a cutover gate, not a request to back-port dozens of
canonical SQL functions into an unledgered PostgreSQL 15 source. Until the
final delta import and canonical activation pass, the Cloudflare deployment is
a public-client candidate and the existing production administration path must
remain available. After activation, the canonical PostgreSQL 17 schema owns
both public and administration contracts.

The final current-client audit on 2026-08-29 expanded this check from the
archived Slunovrat client to every literal RPC reachable from the shared
Flutter and web-client sources. It found 259 required RPC names. The legacy
cloud currently exposes 223 public functions and contains only 97 of those
259 current-client names. The canonical PostgreSQL 17 target exposes 664
public functions and contains all 259 required names; the canonical missing
set is empty. The same backend-surface audit found all 14 invoked Edge
Functions and all 48 directly used `public`/`eshop` relations on the canonical
target. The private evidence is
`slunovrat-client-rpc-contract-final-20260829.json` together with
`slunovrat-backend-surface-postdeploy-20260829.json`.

A complete distinct-name comparison also covered functions not referenced by
the current client. Of 219 legacy names, 213 remain available under the same
name. The six intentional retirements all have explicit canonical successors:

| Retired legacy name | Canonical contract |
| --- | --- |
| `add_transaction_to_payment_info` | authenticated `add_transaction_to_payment_info_ws` |
| `create_companion` | occasion-aware `create_companion_client_sync_v1` and the scoped compatibility facade |
| `delete_form` | `delete_form_client_sync_v1` and authenticated `delete_form_ws` facade |
| `delete_user` | separate owned-companion and occasion-membership deletion commands |
| `get_occasion_user_email` | private service-role-only `get_user_delivery_email` |
| `get_user_companions` | occasion-aware `get_user_companions_data` |

The current client references none of the six retired names. Their removal is
therefore a deliberate security/scope migration, not missing Slunovrat
functionality.

This establishes the intended transition contract: already released clients
continue to use the unchanged legacy backend until activation, while the new
Slunovrat build contains both the transition adapter and the complete modern
canonical contract. Missing modern administration methods are not fabricated
or back-ported into the unledgered legacy database. At activation the frontend
selects the canonical backend as one generation, where public and admin RPCs,
Edge Functions and relations have been deployed together.

The Cloudflare candidate built from version 93 and the canonical tenant overlay
was then exercised against organization `19` / occasion `1072557`. Direct event
detail rendered its description, the in-page back control returned to the
retained Program tab, the occasion root normalized to `/event`, and Program and
Map reads completed against `api.festapp.net` with HTTP 200. This was a browser-
local canonical activation canary only; it did not publish the production
activation manifest or change the external custom-domain DNS.

Client release work must start from current canonical `main` plus a narrow
`festivalslunovrat` tenant overlay. The old production branch is not mergeable:
it predates the overlay policy and contains obsolete shared application code.
Web and iOS require new build-only candidates and private release manifests.
Android configuration can be prepared here, but the signed build remains
deferred to the independent Windows workstation.

## Coordinated three-source recovery point

After the Slunovrat merge, coordinated encrypted backup
`20260828T122654Z` stopped all database-facing runtime writers, proved zero
remaining client sessions, and recorded identical before/after database and
Storage state. Its append-only manifest contains 9,648 Auth users, 1,453
Storage metadata objects, 792 public scopes and all three validated imports.

The backup was restored into clean isolated database
`festapp_restore_2026082812265420260828124702` and a separate Storage path.
The drill matched exactly 1,717 physical files / 1,296,547,327 bytes and the
ordered Storage tree digest. Role attributes, password hashes, memberships,
object owners and normalized effective non-owner ACLs also matched. The only
declared cluster exception is `pg_cron`, which remains confined to the live
`postgres` database. RPO was zero and measured RTO was 790 seconds. The clean
restore cluster was stopped after validation; no cloud source or live target
was mutated and no retained path was deleted.

Retaining every prior successful and failed restore target initially exhausted
the 40 GB rehearsal disk: only about 304 MB remained after this proof. A later
read-only check on 2026-08-30 reported approximately 19 GB free, so this
historical capacity condition is no longer an active blocker. On
2026-08-29 the latest coordinated backup and all three encrypted source
snapshots were rehashed successfully before cleanup. Ten isolated
`festapp_restore_*` databases, 17 restore-drill paths and 12 reproducible
staging/security/obsolete-rehearsal databases were then removed. The live
`postgres` database, canonical `festapp_rehearsal_20260828234500`, production
Storage and off-host encrypted archives were not changed.

The cleanup is recorded under root-only evidence directories
`capacity-cleanup-resume-20260829T140828Z` and
`capacity-staging-cleanup-resume-20260829T140929Z`. It restored 20,038,479,872
bytes of free space (52% of the filesystem). All 12 containers remained
running, all 11 Supabase health checks remained healthy, and the canonical
database still reported 9,648 Auth users, 1,453 Storage objects, three
validated imports and zero non-passing validation gates.

The same-day OneSignal audit made no provider configuration change. App
`slunovratopava` still uses `https://app.festivalslunovrat.cz` for both Chrome
Web Push and Safari, with site name `Festival Slunovrat`. The server-only
credential authenticated against the app configuration endpoint and a
zero-recipient notification canary returned HTTP 200 without notifying any
subscription. Credential replacement remains gated on creating a parallel App
API Key through an authenticated Organization API Key; rotating the existing
key in place would invalidate it immediately and is therefore not an approved
zero-downtime procedure.

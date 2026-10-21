# Canonical schema rehearsal — 2026-08-27

The repository-owned canonical schema is now built on the isolated Hetzner
rehearsal host. This run did not copy production rows, identities or Storage
objects and did not change DNS or either cloud source.

## Applied state

| Item | Verified result |
|---|---:|
| Source commit | `f87dbf47e` |
| PostgreSQL | 17.6 |
| Recorded repository migrations | 101 |
| Public relations | 116 |
| Eshop relations | 40 |
| Auth users | 0 |
| Storage objects | 0 |
| Supabase services | 11/11 healthy |

Root-only evidence is stored on the host at
`/var/lib/festapp-rehearsal-evidence/canonical-schema-20260827T174339Z`.
The original pre-baseline schema snapshot from the first attempt is retained in
the immediately preceding evidence directory.

## Automation finding

The first execution applied the baseline completely, then stopped before the
migration ledger because `psql -c` does not expand the selected variable syntax.
No later migration or source row had been applied. Aggregate and sentinel checks
proved the exact resumable state: zero migration rows, zero Auth users, zero
Storage objects, the three terminal baseline relations present and 113/38
relations in `public`/`eshop`.

Commit `51206bb44` added a one-purpose resume gate and corrected ledger input;
commit `f87dbf47e` corrected PostgreSQL's textual boolean sentinel form. The
resume path accepts only that exact state and has no force, drop or overwrite
mode. It then applied every post-baseline migration and recorded all 101
repository migration versions.

## Capacity snapshot

Immediately after the migration run the 3.98 GB host had 2.16 GB available RAM,
24.22 GB available disk and no recent OOM event. Memory PSI was zero. CPU PSI
`some avg60` was 13.16%, which is recorded as a migration spike and is not a
steady-state pass; the defined acceptance measurement must be repeated after a
settled window and during realistic restore/merge load.

## Next gate

The canonical target catalog was captured after the build. Its private catalog
artifact has SHA-256
`3fb3aef680b5c8fb5769b2d50f7226878a3cbe98193781e6e3db652f3ae5d139` and
the normalized target schema fingerprint is
`574e6ed0d6f3a7e0afad597fec7b20246a7267592d0bdd9944f5f54cb2ffd042`.

The first three-way comparison produced an important blocker:

| Source compared with repository target | Application-schema differences | Platform differences |
|---|---:|---:|
| `default` | 2,075 | 623 |
| `a` | 171 | 637 |

This does not authorize choosing `a` as the canonical data source. It proves
that the current repository baseline is structurally much closer to source `a`
than to `default`, while the approved data identity still starts from
`default`. A naive native `default` schema restore would therefore overwrite or
conflict with a large part of the repository-owned target. The differences must
now be classified as source-only legacy, target expansion or semantic mismatch,
and `default` data must be imported through a reviewed schema boundary rather
than assuming schema equivalence.

Private comparison evidence is stored as `canonical-drift-v2.json`, report
SHA-256 `5cc0f559d8b80d27fb276f4171ee7a528eaa1bc54a6744902899716d222fc38e`.
Importing source rows remains a separate step and must keep both production
sources read-only.

## Logical table-import readiness

The table-level pass narrows the broad catalog drift to the data-bearing import
surface:

| Source | Application tables | Shape-compatible | Blocked transform | Review-only |
|---|---:|---:|---:|---:|
| `default` | 70 | 66 | 2 | 2 |
| `a` | 100 | 100 | 0 | 0 |

No source application table is missing from the target. Source `default` needs
explicit transformations for four `activities` rows because target `order` is
non-null, and for three `user_companions` rows because target `occasion` and
`origin` are required. The `inventory_pools.order` and `log_emails.data` source
columns require an explicit preserve/archive/drop disposition; they may not be
silently discarded. Source `a` is table-shape compatible for logical staging,
but FK, identity, unique-key and embedded-reference transforms remain mandatory.

Private readiness reports are
`default-table-import-readiness-v2.json` (SHA-256
`525978b01c6bdc6b3d2daecf0a7244685482dcd3f03d461aaa3f2f520acb2141`)
and `a-table-import-readiness-v2.json` (SHA-256
`e3ac7e3414e0d259a63af9092afd008d133742be2c6b154b4a54036575748a00`).

A read-only aggregate profile resolved three of the four default transform
families. All four `activities.order` values are non-null, all three obsolete
`inventory_pools.order` values are null, and all 3,882 obsolete
`log_emails.data` values are null. These rules are now fail-closed in
`default-transform-policy.json`.

The remaining blocker is two of three `user_companions` rows. One pair has
exactly one common occasion and can use the repository migration rule. The
other two pairs have no common occasion membership at all and are therefore
legacy orphan relations under the target FK contract. They require an explicit
repair-or-omit deletion-ledger decision; no UUID or identity is stored in Git
and no source row was modified. An earlier exploratory aggregate incorrectly
counted 7 and 42 owner memberships as common memberships; that evidence was
rejected and replaced by the exact inner-match histogram `{0: 2, 1: 1}`.

## Private merge staging

Commit `84e974e14` was transferred as an immutable root-only source directory and
the guarded staging builder completed on the rehearsal host at
`2026-08-27T17:57:39Z`. Evidence is preserved root-only at
`/var/lib/festapp-rehearsal-evidence/merge-staging-20260827T175739Z`.

The additive transaction created four empty tables in the private
`festapp_merge` schema: import runs, ID mappings, quarantined rows and validation
results. Live verification returned `0|0|0|0` rows. Schema usage is false for
`anon`, `authenticated` and `service_role`; Auth and Storage remain at zero and
all 11 runtime services remain healthy. No cloud source was mutated and no
production row was copied.

The quarantine contract preserves any source row that cannot satisfy the
canonical schema and keeps its rehearsal run blocked. It cannot be resolved
without either a repair decision or an `omit-with-ledger` decision tied to a
private evidence checksum. This makes the user's no-deletion constraint an
enforced staging invariant rather than an informal instruction.

## Encrypted rehearsal snapshots and raw staging

Both production clouds remained online and read-only while encrypted rehearsal
snapshots were streamed outside Git to the existing SSH Ed25519 identity. Valid
artifacts are identified only by a sibling manifest and matching SHA-256:

| Artifact | Bytes | Rows | SHA-256 |
|---|---:|---:|---|
| `default.dump.age` | 4,629,627 | application custom archive | `cc00726fbc9f68a86a135699002e04b2643c945abc1b205b3146309c6e62d211` |
| `a.dump.age` | 260,569,205 | application custom archive | `418c6a3421509853e638175fce7d43e96e620cfd4de5cc731acf68e907ddcb05` |
| `default.managed.jsonl.age` | 22,836,739 | 55,317 | `b1a592d778d3a88ae5569569d716e6208df4611e5574d6177fa829b3ecad1e7d` |
| `a.managed.jsonl.age` | 334,409,467 | 802,012 | `8af16cdb817ca9771182dd46c90525fcddb61f0a05ece2f9e9b9b17e35caeea8` |

All files and manifests are `0600` under `0700` directories. Three disabled
audit roles remain in `default` and one in `a`; every role is `NOLOGIN`,
`NOBYPASSRLS`, has no `pg_read_all_data` membership and has zero direct schema
or table grants. They are intentionally not dropped.

The first managed export used 500-row API pages and measured the actual cost of
roughly 1,600 round trips. Production benchmarks proved 10,000-row pages return
the largest Auth payloads in 1.8–2.0 seconds at about 3.5 MB, so subsequent
rehearsals use about 82 requests without parallel source load. During the long
page window `a` changed by 17 rows; this is accepted only as rehearsal evidence
and proves that final state requires a fresh freeze/journal snapshot.

On the Hetzner host, `festapp_stage_default` and `festapp_stage_a` are separate,
non-public PG17 databases. The application restores contain 70 and 100 source
tables respectively; raw managed JSONB staging contains exactly 55,317 and
802,012 rows. All 11 services remained healthy and 22.9 GB disk was available
after staging.

## Default canonical import

The guarded rehearsal import copied all 70 `default` application tables into
the repository-owned canonical schema. It imported 69,916 canonical rows and
preserved the two non-representable legacy `user_companions` rows verbatim in
the private quarantine instead of deleting or silently omitting them. All 172
application foreign keys have zero orphans. Evidence is root-only at
`/var/lib/festapp-rehearsal-evidence/default-canonical-import-20260827T195523Z`.

The follow-up managed import preserved the target runtime's own Auth and
Storage migration ledgers while importing 231 users, 224 identities, 736
sessions, 11,944 refresh tokens, five buckets and 264 Storage metadata rows.
All managed foreign keys have zero orphans. Credential continuity then proved
that 228 password-bearing accounts retain byte-for-byte identical
`encrypted_password` hashes, three accounts remain intentionally passwordless,
and zero users, identities, sessions or refresh tokens are missing. No secret,
identity or password hash is stored in Git.

## Completed canonical merge

The transformed `a` import allocated 431,457 deterministic mappings and copied
all canonical business data with zero application/Auth foreign-key orphans.
Thirteen matching verified e-mail identities were merged under the approved
`verified-email-prefer-default-v1` rule: the default UUID, profile and password
hash remain canonical, while every `a` reference maps to that identity. The
other 6,967 `a` users retain their password hashes byte-for-byte. The combined
Auth state contains 7,198 users, 7,191 identities, 13,751 sessions and 234,236
refresh tokens.

Supabase Storage contains six buckets and 1,199 verified payloads totalling
521,859,566 bytes. Both source copies passed count, size and hash validation and
an actual Storage API range canary. The first failed-path rehearsal files are
still retained outside the canonical tenant layout because this work has no
deletion authority. No merge step wrote to Cloudflare R2.

The 549,293 source `client_%` rows were not copied with stale polymorphic IDs or
old R2 URLs. Their raw snapshot remains private evidence. Canonical derived
state was rebuilt forward-only at revision epoch 76,861: 762 public scopes,
45,942 private vectors, 11,783 aggregate versions and an append-only audit
commit for every occasion. The enabled `csmostrava2026` scope materializes all
six components within publisher budgets; an authenticated private handshake
returns all six current components. Both import runs are now `validated`.

Two default companion relations have no common occasion and therefore cannot
satisfy the target's required occasion/owner/companion foreign keys. They remain
verbatim in the private quarantine, inactive and undeleted. The single
classifiable default relation and two valid `a` relations are active. No
occasion relationship was invented.

## Post-merge capacity result

A four-client/two-thread test executed 200 complete six-component materializer
sets: 200 succeeded, none failed, average latency was 114.301 ms per set and
throughput was 34.995 sets/s. After the test all 11 services were healthy,
`MemAvailable` was 2.05 GB, memory PSI and OOM count were zero, and 20.4 GB
(51%) of the 40 GB disk remained available. The canonical database was 1.155 GB.
This measured rehearsal does not justify a price increase from CAX11. Backup
and restore subsequently passed; a second fresh-snapshot rehearsal remains
mandatory before cutover.

## Semantic reference correction and switch rehearsal — 2026-08-28

The first endpoint canary exposed a real gap that ordinary PostgreSQL FK checks
could not see: `public.events.occasion` is a semantic reference without a
declared FK. The imported rows existed, but 969 CSM Ostrava events still held
source occasion `643` instead of mapped target occasion `1072551`. The target
therefore returned zero events through the released-client fallback path. The
canary blocked cutover before any production switch.

The reference inventory was expanded and repaired forward-only. No row or file
was deleted. The rehearsal now validates:

- scalar references in events, e-mail templates, app-config logs, role info and
  polymorphic planned changes;
- organization JSON defaults and representative occasion IDs;
- blueprint spot IDs and live IDs embedded in order/order-history payloads;
- preserved historical snapshot IDs whose source entity no longer exists;
- transaction audit snapshot IDs, merged-identity UUID references and the
  rebuilt client-sync URL surface;
- the retired inter-project sync as preserved but inert: no cron and no
  `service_role` execute path;
- four remaining legacy Supabase Storage image URLs, all backed by copied
  Storage objects and explicitly gated for rewrite to `api.festapp.net` during
  hostname cutover.

The old-cloud → self-hosted → old-cloud application canary then passed. CSM
Ostrava matched semantically on title and link while IDs were intentionally
remapped. All released-client fallback counts were exact on both endpoints:
26 information rows, 47 news rows, 128 places and 969 events. Client-sync v1
remains deliberately disabled on the rehearsal endpoint until the canonical
publisher/object-origin gate passes; the tested database fallback is complete.

## Encrypted post-fix recovery point

An append-only encrypted backup was created outside the repository as run
`20260827T220127Z`, then restored into new isolated database
`festapp_restore_2026082722012720260827221138` and a new Storage path. The drill
matched 7,198 Auth users, 1,199 Storage metadata rows, 762 public scopes, two
validated imports and exactly 1,463 physical files / 606,950,851 bytes. It
wrote no plaintext backup artifact, changed neither cloud source nor the live
rehearsal database, and deleted no path. All 11 services remained healthy.

The second complete merge from a newer snapshot passed on 2026-08-28; see
`second-canonical-rehearsal-2026-08-28.md`. The remaining production gates are
the final freeze/journal snapshot, canonical hostname and the complete
registered legacy-URL rewrite,
compatible web/Android/iOS releases, Auth/rights/write canaries, and the final
write-authority/DML gate.

The dynamic repair/validation sequence was also rerun end-to-end against the
earlier isolated pre-fix restore database. It derived repair counts from that
snapshot and the deterministic map rather than today's fixed cardinalities.
All four phases passed, the restored CSM scope moved from 969 rows on old
occasion `643` to 969 on target `1072551`, and every validation result passed.
This proves script repeatability independently of the already-repaired live
rehearsal database; it is not a substitute for the required newer cloud
snapshot rehearsal.

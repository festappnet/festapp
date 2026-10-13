# Image delivery readback - 2026-10-07

Read-only production verification, approximately 11:52-12:00 UTC. No app,
Worker, object, route, custom domain or store release was changed. Existing
Wrangler OAuth authenticated account `84b32318ac235bf6738bdf1c8caa0795`;
zone `02fd6ca8f4652d62e9b05f24a5e9d84f` belongs to that account.

## Routing and deployed Worker

The Cloudflare API reports all four custom domains (`img.festapp.net`,
`a.img.festapp.net`, `akh.img.festapp.net`, `image-api.festapp.net`) attached
to `festapp-image-worker`. None of the three public R2 buckets has a custom
domain. P3 has therefore not happened. The latest deployment is
`63e8aab7-74fa-48e3-9d59-18bafaa9258c`, deployed 2026-10-02 00:27:48 UTC.
`PRIVATE_MIGRATION_FALLBACK` is `disabled`; this does not prove its source
or other migration compatibility paths have been removed.

The deployed script, retrieved with a GET of the Worker script resource,
registers exactly `default`, `a`, `akhweb`; it contains no `slunovrat` literal.

## Public R2 bucket inventory

GET object listings returned one complete page per bucket, below the requested
1,000-object page size. Only aggregate counts were recorded, without object
names, private paths or credentials.

| Bucket | Objects | Bytes | `private/` objects | Outside registry public prefixes |
|---|---:|---:|---:|---:|
| `festapp-images` | 390 | 150,700,631 | 0 | 99 |
| `festapp-images-a` | 664 | 187,091,477 | 0 | 5 |
| `festapp-images-akhweb` | 514 | 223,192,486 | 0 | 0 |

The registry allows `images/` for default/a and `images/`, `blog/`, `content/`
for akhweb. The 104 other objects have not been classified as public or
private; they are not proven deletion candidates. None has a `.pdf` suffix.
Zero `private/` objects alone does not satisfy P3's zero-nonpublic-object gate.
The current public serving code reads bucket keys generally; this inventory
does not imply that every non-registry prefix is newly exposed by direct R2.

## Current web clients and source

After fetching origin, all 11 active tenant public activation documents report
their expected tenant, `backend=canonical`, generation 1. Each manifest-selected
Flutter bundle contains `https://image-api.festapp.net`. This is a deployed
origin check, not proof of successful authenticated uploads or native adoption.

Ten web manifests report `0.20.134+618`; festapptickets reports `0.20.133+617`.
CSM's current source is `e9d49e409b013757b67e3adaf03de141c02046a6`,
`0.20.135+619`, while its web deployment reports `0.20.134+618`.
No build or rollout was triggered to resolve that version difference.

The current festivalslunovrat branch is
`bbbd97ca851255fb3f3d87f87e3e523e45540397`. Its config and generated Dart
declare `projectId=slunovrat`. Its deployed `0.20.134+618` bundle contains that
literal adjacent to the control origin. The running Worker has no matching
project. Resolve the correct server-owned backend/bucket mapping before
changing either side; do not guess that `a` is equivalent or broaden rollout.

## Legacy traffic

Cloudflare `httpRequestsAdaptiveGroups`, 2026-09-07 11:57:58 UTC through
2026-10-07 11:57:58 UTC, queried the three public image hosts with exact
`/upload`, `/delete` and prefix `/private/`, `/presign/` filters. The query
returned 43 groups, below its 10,000-group limit. No upload, delete or presign
group was observed. Private groups all returned 401, including one reported
request on img on October 5 and one on a.img on October 6. Sampling intervals
range from 1 to 8. These are rejected attempts, not proven legacy app users;
sampled analytics cannot establish exhaustive zero traffic or caller identity.

## Decision

Keep the image Worker and compatibility code. P3/P4 remain open because direct
R2 routing is absent, non-registry objects are unclassified and native adoption
is unverified. First reconcile the Slunovrat project contract and classify
the 104 objects without deleting them. Then inspect current native store/client
state and establish the plan's adoption window or approved minimum version.
Only after those gates should the exact host set, rollback state and routing
change be prepared. Historical Windows commands 1025-1028 are not next steps.

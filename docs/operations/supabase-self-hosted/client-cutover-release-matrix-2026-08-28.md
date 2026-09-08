# Client cutover release matrix — updated 2026-09-08

This is the authoritative client scope for the canonical Supabase cutover. It
defines release lanes, not historic binaries: each active mobile identity needs
one new transition release, and each active web deployment needs one regenerated
transition deployment. Older writers must then be excluded by enforced minimum
version/adoption evidence or by the maintenance freeze.

This public matrix records only public application identities, origins and
coarse gate states. Store-account readback, reviewer data, signing/provider
receipts and exact artifact evidence belong exclusively in the private release
repository and must not be copied here.

## Mobile release lanes

| Product / production refs | iOS bundle / observed lower bound | Android package / observed lower bound | Required disposition |
| --- | --- | --- | --- |
| Festapp (`prod/festapp`, `prod/festapptickets`) | `festapp.festapp` / `0.19.95 (478)` live | `fstapp.fstapp` / `>388` | Android publication is explicitly excluded; close this identity as technically read-only or retired. Resolve the duplicate web deployment owner separately. |
| CSM (`prod/csmostrava2026`) | `festapp.jm2025` / `0.19.95 (467)` live | `fstapp.jm2025` / `0.20.1 (485)` live | Android full rollout and soft update prompt are live; collect adoption or close the lane as technically read-only during the freeze. The historical Jubilee ref remains web-only. |
| Hvězda Mořská (`prod/hvezdamorska`) | `festapp.hvezdamorska` / `0.19.95 (468)` live | `fstapp.hvezdamorska` / `0.20.1 (485)` live | Android full rollout and soft update prompt are live; adoption/read-only evidence remains. |
| Festival Slunovrat (`prod/festivalslunovrat`, `prod/slunovratopava`) | `festapp.festivalslunovrat` / `0.19.95 (479)` live | `fstapp.slunovratopava` / `0.20.1 (485)` live | Android full rollout and soft update prompt are live; adoption/read-only evidence remains. |
| Absolventský Velehrad (`prod/absolventskyvelehrad`) | `festapp.absolventskyvelehrad` / `0.19.95 (468)` live | `fstapp.AV25` / `0.20.1 (485)` live | Android full rollout and soft update prompt are live; physical-device and adoption/read-only evidence remain. |
| Člověk a víra (`prod/cavfotofest`) | `festapp.cavfotofest` / `0.19.95 (466)` live | `fstapp.cav` / `0.20.1 (485)` live | Android full rollout and soft update prompt are live; physical-device and adoption/read-only evidence remain. |
| Do O BiS Cup (`prod/doobiscup`) | `festapp.doobiscup` / `0.19.95 (473)` live | `fstapp.diecezkodoo` / `0.20.1 (485)` live | Android full rollout and soft update prompt are live; physical-device and adoption/read-only evidence remain. |
| Celostátní setkání animátorů / CSA 2024 (`prod/aksmcz`) | listed historical version only; no new release | public listing 404; no new release | Web-only `0.19.93+475` is live at `csa2024.festapp.net`, without OneSignal; old Netlify redirects path/query. Canonical organization is `4`. App Store removal from sale remains a separate store operation. |
| Farnost Opava (`prod/farnostopava`) | shared historical IDs; no new lane | shared historical IDs; no new lane | Proven web-only at `farnostopava.festapp.net`, with no OneSignal and no iOS/Android release. `rezervace.farnostopava.cz` is now a path/query-preserving retirement redirect; no WEDOS handoff remains. |
| AVApp (`prod/avapp`) | `festapp.festapp` / `>45` (collides with current Festapp identity) | `vkhcr.avapp` / `>45` | Old backend hostname is dead and the modern AV tenant is already canonical. Retire/read back the old Android listing; never create a second iOS upload under the Festapp identity. |
| TicketOnline (`prod/ticketonline`) | `festapp.aksmcz` / `>236` (shared legacy identity) | `fstapp.fstapp` / `>236` (shared Festapp identity) | The singular `vstupenka.online` client is the same default organization `3` as canonical `vstupenky.online`; retire it as a path/query-preserving compatibility alias, with no new mobile build. |

The table is deliberately conservative: every distinct identity or ambiguous
identity reuse found in `origin/prod/*` is represented. A shared bundle/package
is one store lane but may have several tenant entry paths that all need canaries.
The observed build numbers are lower bounds from repository release state, not
authority to reuse a number. App Store Connect and Play Console readback must
confirm the actual listing and next number before upload. iOS and Android are independent lanes:
success on one platform never closes the other. We do not republish every old
version. We publish one compatible transition version per active identity and
prove that an older cloud-writing version cannot remain an accepted writer at
cutover.

### Android transition release evidence — 2026-09-08

The six authorized Android identities above were independently read back from
Google Play production at version `0.20.1 (485)` with release status
`completed` (full rollout). Their source organizations now advertise `0.20.1`
through the existing `PLATFORMS.droid.prompt` and retain their matching Play
Store links. This is a dismissible in-app update prompt, not a hard minimum
version gate; it therefore improves migration pressure but does not by itself
prove that older writers are absent. Store adoption telemetry or the
technically enforced maintenance freeze must close that remaining condition.
`fstapp.fstapp` was excluded from the release and prompt changes.

Each mobile row closes only when its private evidence records all of:

- shared source commit and tenant overlay commit;
- release-manifest SHA-256 and pinned activation-document SHA-256;
- legacy and mapped canonical organization IDs plus the canonical cache-generation proof;
- bundle/package ID, semantic version and build/version code read back from the
  signed IPA/AAB;
- signed artifact SHA-256, signing identity and store listing match;
- store state plus active-build/minimum-version adoption evidence;
- legacy-phase cold start and write canary;
- canonical-phase full-process restart, refresh/session canary and write canary;
- confirmation that warm foreground alone does not claim to switch a running
  Supabase singleton.

Ordinary retained accounts should not need to log in again: the stable storage
namespace and imported refresh token are exchanged against canonical Auth. The
five approved Slunovrat identity merges are the recorded exception because
their superseded source sessions were intentionally not imported; those five
accounts may require ordinary reauthentication.

## Web deployment lanes

All 11 active production refs were regenerated from current `main` and deployed
successfully on 2026-09-04. Their public activation documents return `200`,
`Cache-Control: no-store, max-age=0`, `backend=legacy` and `generation=0`.
Every bundle therefore remains on its current cloud source while carrying one
pinned canonical `api.festapp.net` profile for the final atomic activation.

| Production ref | Public site | Source organization → canonical organization |
| --- | --- | --- |
| `prod/absolventskyvelehrad` | `app.absolventskyvelehrad.cz` | `a`: `5→8` |
| `prod/aksmcz` | `csa2024.festapp.net` | `a`: `1→4`; web-only |
| `prod/cavfotofest` | `clovekavira.festapp.net` | `a`: `3→6` |
| `prod/csmostrava2026` | `csmostrava.festapp.net` | `a`: `9→12` |
| `prod/doobiscup` | `biscup.festapp.net` | `a`: `2→5` |
| `prod/farnostopava` | `farnostopava.festapp.net` | `a`: `8→11`; web-only |
| `prod/festapp` | `live.festapp.net` | `default`: `1→1` |
| `prod/festapptickets` | `vstupenky.online` | `default`: `3→3`; canonical ticket-web owner |
| `prod/festivalslunovrat` | `slunovrat.festapp.net` | `slunovrat`: `1→19` |
| `prod/hvezdamorska` | `hvezdamorska.festapp.net` | `a`: `4→7` |
| `prod/jubileum2025` | `jubileum2025.festapp.net` | `a`: `6→9`; web-only |

The three refs without `automation/project.conf` are closed, not pending:
`prod/avapp` has a dead historical backend and removed Play listing;
`prod/slunovratopava` redirects to the canonical Slunovrat owner; and
`prod/ticketonline` redirects path/query to `vstupenky.online`. Farnost's former
WEDOS-hosted application URL now redirects path/query to
`farnostopava.festapp.net`, so a CNAME handoff is no longer required.

The web preparation lane is complete. During the maintenance window every site
still needs a fresh legacy freeze observation followed by canonical activation,
full reload, refresh/reauth, rights and idempotent-write canaries. A successful
deployment is not itself canonical activation evidence.

Each web row requires source SHA, generated config digest, deployed bundle
digest, public activation document with `no-store`, cold-load legacy and
canonical canaries, refresh/session evidence, and confirmation that service
worker/CDN caching cannot retain the legacy activation. Web/admin surfaces not
represented by a production ref must be added before they write.

## Non-client writers

Edge Functions, cron jobs, callbacks, workers, manual scripts and direct SQL
clients close under the write-authority matrix rather than a store release.
Their endpoint, credential owner, DML/journal coverage and freeze behavior must
all be known. Store approval or a successful client build cannot compensate for
an unknown non-client writer.

## Gate

The cutover gate passes only when every lane is one of:

1. transition artifact deployed and adopted with both phase canaries passing;
2. technically enforced read-only for the entire freeze/cutover window; or
3. proven unreachable/retired using deployment, DNS and write telemetry.

“Uploaded”, “approved”, “probably unused” and “works on one platform” are not
closed states. The six authorized Android transition releases have completed
their build/signing/publication gate; their remaining gate is fresh adoption or
technically enforced read-only evidence plus both cutover-phase canaries.

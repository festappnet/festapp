# Client cutover release matrix — updated 2026-09-02

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
| Festapp (`prod/festapp`, `prod/festapptickets`) | `festapp.festapp` / `0.19.95 (478)` in review | `fstapp.fstapp` / `>388` | Complete Apple review and publish/prove the canonical transition release on Android. Resolve the duplicate web deployment owner separately. |
| CSM (`prod/csmostrava2026`) | `festapp.jm2025` / `0.19.95 (467)` ready for sale | `fstapp.jm2025` / `>450` | Apple release is live; complete Android release and adoption proof. The historical Jubilee ref remains web-only. |
| Hvězda Mořská (`prod/hvezdamorska`) | `festapp.hvezdamorska` / `0.19.95 (468)` in review | `fstapp.hvezdamorska` / `>451` | Complete Apple review and Android release, then prove adoption. |
| Festival Slunovrat (`prod/festivalslunovrat`, `prod/slunovratopava`) | `festapp.festivalslunovrat` / `0.19.95 (479)` in review | `fstapp.slunovratopava` / production `479` | Complete Apple review. Android needs a code strictly above `479` and remains deferred to the independent Windows workstation. |
| Absolventský Velehrad (`prod/absolventskyvelehrad`) | `festapp.absolventskyvelehrad` / `0.19.95 (468)` in review | `fstapp.AV25` / `>243` | Complete Apple review, Android release and physical-device/adoption proof. |
| Člověk a víra (`prod/cavfotofest`) | `festapp.cavfotofest` / `0.19.95 (466)` in review | `fstapp.cav` / `>243` | Complete Apple review, Android release and physical-device/adoption proof. |
| Do O BiS Cup (`prod/doobiscup`) | `festapp.doobiscup` / `0.19.95 (473)` in review | `fstapp.diecezkodoo` / `>243` | Complete Apple review, Android release and physical-device/adoption proof. |
| Celostátní setkání animátorů / CSA 2024 (`prod/aksmcz`) | listed historical version only; no new release | public listing 404; no new release | Web-only `0.19.93+475` is live at `csa2024.festapp.net`, without OneSignal; old Netlify redirects path/query. Canonical organization is `4`. App Store removal from sale remains a separate store operation. |
| Farnost Opava (`prod/farnostopava`) | shared historical IDs; no new lane | shared historical IDs; no new lane | Proven web-only at `0.19.93+474`, with no OneSignal and no iOS/Android release. Cloudflare bundle is ready; the identical Netlify hybrid remains public only until the external WEDOS owner changes CNAME `rezervace` to `farnostopava.pages.dev`. |
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

The following production refs have an identified generated configuration and
must be regenerated from the shared transition source, deployed atomically and
verified by completed-bundle inspection:

| Production ref | Public site | Source family |
| --- | --- | --- |
| `prod/absolventskyvelehrad` | `app.absolventskyvelehrad.cz` | `a` |
| `prod/cavfotofest` | `clovekavira.festapp.net` | `a`, organization `3→6` |
| `prod/csmostrava2026` | `csmostrava.festapp.net` | `a`, organization `9→12` |
| `prod/doobiscup` | `biscup.festapp.net` | `a`, organization `2→5` |
| `prod/farnostopava` | `rezervace.farnostopava.cz` | `a` |
| `prod/festapp` | `live.festapp.net` | `default` |
| `prod/festapptickets` | `vstupenky.online` | `default`; canonical ticket-web deployment owner |
| `prod/hvezdamorska` | `hvezdamorska.festapp.net` | `a`, organization `4→7` |
| `prod/jubileum2025` | `jubileum2025.festapp.net` | `a`, organization `6→9`; web-only, with no iOS/Android release |
| `prod/aksmcz` | `csa2024.festapp.net` | `a`, organization `1→4`; web-only, with no OneSignal or mobile release |

Three retired/duplicate legacy refs currently lack `automation/project.conf`:
`prod/avapp`, `prod/slunovratopava`, and `prod/ticketonline`.
Each must receive exactly one documented disposition before cutover: restore a
canonical tenant overlay and deploy it, enforce read-only behavior, or prove
from hosting/DNS/traffic/write telemetry that it is retired. Branch age is not
retirement evidence.

The active Cloudflare web lanes use Flutter `3.47.2` and semantic version
`0.19.93`. The current ticket web uses build `476` and `live.festapp.net` uses
build `477`; other deployed tenant builds retain their independently monotonic
build numbers. Build numbers are monotonic within each
release lane and are not expected to be identical across unrelated store/web
identities. The three source-a web overlays remain deliberately in `legacy`
activation phase while carrying their mapped canonical organization and
`api.festapp.net` configuration, so the final activation document can switch
them after the full-freeze gate without rebuilding the bundle. Festapp `477`
now carries the equivalent source-default transition profile for canonical
organization `1`, while its public activation document remains in `legacy`.

Jubilee is now deployed independently as web-only build `0.19.93+473` at
`jubileum2025.festapp.net`, from overlay `77093978881186b9d25cedd88a5a355e05a60d36`.
Its released bundle has no OneSignal configuration and creates no mobile/store
lane. The historical dashboard naming/state was corrected without changing the
active CSM client identity; tenant-specific provider evidence is retained in
the private release repository. Its old Netlify origin is a pure
301 compatibility surface, except for retirement worker responses that remove
historical PWA/push registrations. The remaining Jubilee gate is therefore
only the shared freeze, delta import, activation and retained-session/write
canary.

Farnost Opava is deployed as web-only build `0.19.93+474` from overlay
`ea5e608410a84d24bb4bf7120347b24304243e05`. It starts on source-`a`
organization `8`, pins canonical organization `11`, preserves the legacy Auth
storage namespace, and intentionally has no OneSignal IDs. Cloudflare origin
verification and public Netlify-hybrid browser QA pass. The application lane is
complete; only the external WEDOS CNAME handoff remains before Cloudflare owns
the public hostname and Netlify can become a redirect-only compatibility edge.

The Festapp `477` production smoke passes the canonical root-to-program
redirect, both legacy `get_events` reads, a program detail with its full HTML
description, detail back-navigation to `/conference2024/event`, the public
login route and the Flutter admin route. `backend-activation.json` is served as
JSON with `no-store, max-age=0`; internal application links and the iOS
associated-domain input now use `live.festapp.net`, not the separate
`vstupenky.online` tenant. The stable legacy Auth storage namespace is retained,
so installing this transition web build does not itself sign users out.

Festival Slunovrat now has a canonical version-93 overlay on
`prod/festivalslunovrat`, a successful Cloudflare candidate at
`festivalslunovrat.pages.dev`, complete canonical client RPC/Edge/relation
coverage, a published 28.4 MiB immutable offline-map v2 bundle and a signed,
non-uploaded iOS build-only candidate whose production push/app-group/domain
entitlements passed. Its custom domain, physical-device/native offline
acceptance, Android Windows build and backend activation remain gated. The historic
`prod/slunovratopava` ref is not a second release source and still needs an
explicit archival/retirement disposition before cutover.

Absolventsky Velehrad now has a canonical version-93 overlay on
`prod/absolventskyvelehrad` and production web build `0.19.93+467` at
`app.absolventskyvelehrad.cz`. Its cold-load production smoke reached the
program route with no browser console errors, initialized OneSignal, and served
the legacy-phase activation document as JSON with `no-store`. Apple Developer
now assigns the existing `group.festapp.festapp.onesignal` group to both the
main bundle and notification extension. A signed, non-uploaded iOS candidate
from source `73e3706d390d7291c557cb8b0b8c56feec311068` passed production push,
shared app-group, associated-domain, extension-identity and prohibited-location-
framework checks. Physical-device/native acceptance, the App Store release and
the Android Windows build remain gated; the informational root
`absolventskyvelehrad.cz` remains separate from the app subdomain.

Clovek a vira now has a canonical version-93 overlay on `prod/cavfotofest`
and production web build `0.19.93+465` at `clovekavira.festapp.net`. Apple
Developer App Group assignments were reduced from three historical groups to
the single tenant group `group.festapp.cavfotofest`, and the notification
extension was assigned that same group. Regenerated profiles and a signed,
non-uploaded iOS candidate from source
`c10a33dfd0f1e147be6e8674942b4b2d65df0754` passed production push, app-group,
associated-domain, extension-identity and prohibited-location-framework checks.
Physical-device/native acceptance, App Store release and Android Windows build
remain gated.

BISCUP now has a canonical version-93 overlay on `prod/doobiscup` and
production web build `0.19.93+472` at `biscup.festapp.net`. The old
`biscup.netlify.app` origin preserves deep paths through HTTP 301 and retains
only the retirement/PWA compatibility workers. OneSignal's saved web origin was
changed to the canonical domain; a fresh browser session then initialized it
without an origin error. Apple Developer now assigns only
`group.vkhcr.doobiscup.onesignal` to both bundle IDs, and the regenerated
profiles produced a signed, non-uploaded iOS candidate from source
`72d5a399272b7ac2dcdada1f298a9d486a0d779e`. Direct IPA inspection passed
production push, app-group, associated-domain, extension-identity and
prohibited-location-framework checks. Physical-device/native acceptance, App
Store release and Android Windows build remain gated.

The Hvezda Morska `466` production smoke passes the all-unit catalogue root,
occasion detail, reservation handoff to `/form/povyseni2026`, and the Flutter
`/admin` handoff. The provider's saved web origin is canonical; its exact
dashboard receipt is retained only in the private release repository. A cold
production check completed OneSignal initialization without an origin error,
and the custom
`/push/OneSignalSDKWorker.js` returned JavaScript. The old Netlify root and a
deep `/form/rijnovapout26` URL both return HTTP 301 to the same path on the new
origin. This closes the Hvezda web-push origin gate. Browser subscriptions
cannot be transferred between origins, so users must opt in on the new origin;
that expected re-subscription does not require another bundle build.

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
closed states. Android compilation/signing evidence is completed later through
the approved Windows build workstation; all source, manifest and preflight
inputs must be fixed before that command is sent.

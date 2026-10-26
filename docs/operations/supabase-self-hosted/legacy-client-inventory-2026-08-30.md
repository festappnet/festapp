# Legacy Festapp client inventory — 2026-08-30

The repository and hosting inventory found four production refs without the
canonical `automation/project.conf` contract. They must not be rebuilt as a
batch. Each receives one explicit release, replacement or retirement decision.
Private inventory evidence is stored outside the repository at
`~/.local/share/festapp-rehearsal-20260830/legacy-tenant-config-inventory.json`.
A second scan covered all 33 remote refs, including feature, rehearsal and
cutover refs, rather than only `prod/*`. Its private result is
`~/.local/share/festapp-rehearsal-20260830/all-remote-client-config-inventory.json`
(SHA-256 `2f8348663c6bf1bd510bfdf7143ee96a6c31ae73d22de3855e311a4639dc2549`).
Eighteen refs contain a client configuration, but they collapse to the already
registered production identities plus CSM rehearsal/feature snapshots. No
additional historical application was found outside the 14 production refs.

## `prod/aksmcz` / Celostátní setkání animátorů (CSA 2024)

The branch is a real historical tenant, not an unused test. It is pinned to
source `a`, organization `1`, occasion `csa2024`, and app name `CSA 2024`.
That occasion ran from 12–17 August 2024 and contains 391 events and 340
occasion-user relations. The canonical merge preserved it as organization `4`
and occasion `1072505`.

`aksmcz.netlify.app` still serves the old application, while its recorded
custom origin `app.rawen.dev` no longer resolves. The approved disposition is
web-only: rebuild the tenant from current `main` at `csa2024.festapp.net`, keep
the legacy backend active behind the signed resolver until cutover, and then
retire the Netlify origin with a path/query-preserving redirect. No Android,
iOS or OneSignal release belongs to this lane.

Public App Store readback found the still-listed `CSA 2024`, Apple ID
`6479449613`, bundle `festapp.aksmcz`, version `0.13.0`, last released on
12 May 2025. The public Google Play URL for package `fstapp.csa` returns 404.
The Apple listing therefore remains a real external consumer. It receives no
new build; removing it from sale is a separate App Store operation and is not
performed by the web/backend cutover.

The web-only transition is now deployed as `0.19.93+475` at
`csa2024.festapp.net`. Its program and event detail load from source `a`, the
detail back action returns to the program, and the legacy Netlify hostname
redirects path and query to the canonical domain after retiring its cached
service worker. Source-`a` Auth allows both canonical reset-password paths.

This is the older “Setkání animátorů” application referred to in operational
discussions; it is not an additional fifteenth production ref. The repository
acronym `aksmcz` and the public listing name `CSA 2024` identify the same lane.

## `prod/farnostopava` / Rezervace Farnost Opava

Farnost Opava is now proven web-only. Release `0.19.93+474` is based on main
`67b49c3e4916009841c50006c8f3e4251313d23d` and production overlay
`ea5e608410a84d24bb4bf7120347b24304243e05`. It retains source-`a`
organization `8`, pins canonical organization `11`, preserves the source-`a`
Auth storage namespace, and has no OneSignal configuration or mobile release.

Cloudflare Pages deployment `bf422d3c.farnostopava.pages.dev` passes the
coherent release verifier. The public `rezervace.farnostopava.cz` surface is
temporarily serving the identical static adapter from Netlify deployment
`6a937f193b8c71ae6664bf26`; root, form and admin routes return 200, the visible
tenant heading is correct, and browser QA observed zero OneSignal resources.
Cloudflare has accepted the custom-domain binding, but DNS remains externally
blocked: the WEDOS-hosted `farnostopava.cz` zone is not present in the available
WEDOS account. Its owner must change only CNAME `rezervace` from
`farnostopava.netlify.app` to `farnostopava.pages.dev`. After Cloudflare reports
the domain active, the Netlify origin can be reduced to the registered
path/query-preserving retirement surface without another application build.

## `prod/avapp`

This is the pre-canonical Absolventský Velehrad client, version `0.7.4+45`.
Its old Supabase hostname `jyghacisbuntbrshhhey.supabase.co` no longer resolves,
and the modern tenant is already owned by `prod/absolventskyvelehrad` at
`app.absolventskyvelehrad.cz`. Public Google Play readback on 2 September 2026
returns 404 for the old Android identity `vkhcr.avapp`. Together with the dead
historical backend and the active replacement tenant, this closes the retirement
boundary without creating or uploading another application. Its historical iOS
identity collides with the current Festapp lane and must not be uploaded
independently.

## `prod/slunovratopava`

This is an obsolete duplicate of `prod/festivalslunovrat`, last updated in
2024. The canonical Slunovrat source, web origin and mobile identities are now
owned by `prod/festivalslunovrat`; the old branch must not generate a second
release. On 2 September 2026, `slunovrat.netlify.app` returned a
path/query-preserving HTTP 301 to `app.festivalslunovrat.cz`, its historical
worker paths contained only retirement payloads, and the canonical destination
returned 200. The Android package `fstapp.slunovratopava` is the existing
canonical Slunovrat listing rather than a second legacy lane. This closes the
legacy branch's external retirement boundary.

## `prod/ticketonline` / `vstupenka.online`

The singular-domain client and canonical `vstupenky.online` both use the
default Supabase project, organization `3`, no forced occasion and no Flutter
application surface. The singular site has no activation document and serves
an obsolete full Flutter bundle. It is therefore a compatibility alias, not a
separate tenant.

The canonical-cutover contract is HTTP 301 from `vstupenka.online` to the same
path and query on `vstupenky.online`, while historical Flutter, Festapp and push
worker URLs return only an unregister/cache-retirement worker. The registered
deployment is generated by `automation/build_netlify_retirement.mjs` and
applied through the acknowledged `automation/deploy_netlify_retirement.sh`;
the retired origin contains no application or Edge Function implementation.
Production Netlify deploy `6a9375a25c482a6d9d81f2c0` passed that contract,
and `prod/ticketonline` commit `f4ab1601e2f5bb8d93a0249e2f6f4cdc5c8c558b`
now prevents future automatic builds from restoring the obsolete Flutter app.

## Inventory result

Fourteen production refs were inspected: ten have canonical configurations and
four originally lacked them. Farnost Opava has since been closed as a web-only
lane, while the four legacy dispositions listed in the release matrix remain
tracked explicitly. The remaining broad source-`a` entries are not
unknown tenants; they are all-unit catalogue clients whose write reachability
still closes under the shared freeze/write-authority gate. No Android or iOS
build is authorized by this inventory.

# Public web analytics

Cloudflare Web Analytics measures public catalogue, organizer and resolved form pages only. Each link below has a fixed exact-host filter; zone-backed sites share storage and use per-host views; Velehrad has its own manual site card. Requests/server statistics remain separate.


Use the [combined Festapp + Velehrad overview](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8%2Ccddce39c98cd4949b882c865471ab50d&excludeBots=Yes) to view the Festapp-domain apps and Velehrad together. The dashboard was verified to show `Site is in festapp.net, app.absolventskyvelehrad.cz`; use Host to separate individual websites. The filter includes these two properties only, not every analytics site in the account.

Cloudflare's [same-domain restriction](https://developers.cloudflare.com/web-analytics/faq/#can-i-use-the-same-js-snippet-for-a-different-domain) prevents moving a `.cz` hostname into the `festapp.net` collection property. The combined dashboard is the supported reporting group; Velehrad keeps its working exact-host collector identity. No tenant deployment or domain change is needed for this report grouping.

| Host | Rollout status (2026-10-25) | Public visits and sources |
| --- | --- | --- |
| app.absolventskyvelehrad.cz | 0.20.392+893; dedicated manual site, POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=cddce39c98cd4949b882c865471ab50d&host=app.absolventskyvelehrad.cz&excludeBots=Yes) |
| biscup.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=biscup.festapp.net&excludeBots=Yes) |
| clovekavira.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=clovekavira.festapp.net&excludeBots=Yes) |
| csa2024.festapp.net | Unchanged by user request | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=csa2024.festapp.net&excludeBots=Yes) |
| csmostrava.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=csmostrava.festapp.net&excludeBots=Yes) |
| farnostopava.festapp.net | Unchanged by user request | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=farnostopava.festapp.net&excludeBots=Yes) |
| hvezdamorska.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=hvezdamorska.festapp.net&excludeBots=Yes) |
| jubileum2025.festapp.net | Unchanged by user request | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=jubileum2025.festapp.net&excludeBots=Yes) |
| live.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=live.festapp.net&excludeBots=Yes) |
| slunovrat.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=slunovrat.festapp.net&excludeBots=Yes) |
| tickets.festapp.net | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=3335204bc4014e9c9e8d7568920650f8&host=tickets.festapp.net&excludeBots=Yes) |
| vstupenky.online | 0.20.391+892; collector POST 204 verified | [Web Analytics](https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/web-analytics/overview/visits?siteTag~in=4b64cee2415d4110b11abc4d56013278&host=vstupenky.online&excludeBots=Yes) |

Use the Referer breakdown for source domains such as Google. Missing referrers cannot distinguish direct links from applications that hide their source. The provider does not report search terms or UTM campaigns.

## Release evidence

The initial nine selected web releases used source `be3a27ccd3fd1bfae34938ad7636f0c7f779591d` and version `0.20.391+892`; each passed its local build and three coherent live version/assets/legal probes. The three explicitly excluded tenants were not released.

Browser checks verified one beacon, `spa: false`, and successful collector POST 204 on all nine working sites after the Velehrad follow-up. On Hvězda mořská the same public form crossed into a fresh scanner document with zero beacons, and the captured analytics payload contained no synthetic private code. Private fragments and administration were also excluded. Stored Cloudflare GraphQL data independently showed Czech visits under the exact Hvězda mořská hostname.

Velehrad follow-up: its previous zone-backed collector returned 404. A dedicated manual site for `app.absolventskyvelehrad.cz` now owns its public-page measurement, using the official external Cloudflare collector. The original parent-zone analytics setup is preserved. The Velehrad-only follow-up is deployed at `0.20.392+893` from source `6d6a72f79c52df9a73ab5150ef42e92f37152de0` (tenant `4e1f9cafb4731035b73c4b2c8e4ed8d9c23e6d21`). Its three coherent live probes passed. The unmodified deployed public form sent a successful POST 204; a real navigation to the scanner loaded zero beacons and the payload contained no synthetic private code. The dedicated property also contains stored Czech visits. The other eight production tenants were not changed in this follow-up.

## Collection boundary

- Pages response owners insert the bootstrap only into the public catalogue, organizer landing page and resolved public forms. Flutter, scanner, authentication, payments, PWA cache shells, static legal pages and embeds have no beacon.
- Every HTML response uses `Cache-Control: no-transform` to prevent zone-wide automatic injection. The organizer renderer never inserts a beacon into shared app shells.
- The bootstrap rejects fragments, private query parameters, framed documents and non-public referring paths. Only origin-only external referrers and same-host public referrers are accepted. This intentionally undercounts some arrivals rather than sending private URLs.
- Existing zone-backed properties send the official beacon to their built-in same-origin `/cdn-cgi/rum` endpoint; the manual vstupenky.online and app.absolventskyvelehrad.cz properties use the default external Cloudflare collector. Browser checks must verify a successful POST, not just beacon initialization.
- A single manual Cloudflare beacon uses `spa: false`. Measured pages cross a real document boundary for pathname changes, including history API navigation. Same-path order/waitlist fragments retain normal overlay behavior. A beacon cannot follow a public page into scanner/admin paths.
- No Do Not Track/GPC gate, analytics cookies, persistent visitor identifiers, form fields, account IDs, order IDs or custom collector are added. The provider still receives network transport information. This is a technical collection description, not a blanket claim that all website processing is anonymous.
- Existing site tags and tokens in the registry are public embed identities, never management credentials. Preview origins and unregistered hosts cannot use this configuration.

## Verification

`node --test automation/tests/public_web_analytics.test.mjs automation/tests/cloudflare_security_headers.test.mjs automation/tests/public_seo.test.mjs automation/tests/organizer_page.test.mjs automation/tests/csp_policy.test.mjs`

A release additionally verifies one manual beacon on eligible public pages, none on private routes or private fragments, no automatic duplicate, and a real public-to-private navigation boundary. Inspect actual provider payloads for private path leakage. Existing open tabs need a reload to pick up a release.

References: [Cloudflare SPA opt-out](https://developers.cloudflare.com/web-analytics/get-started/web-analytics-spa/), [automatic injection and no-transform](https://developers.cloudflare.com/web-analytics/faq/), [dimensions and referrers](https://developers.cloudflare.com/web-analytics/data-metrics/dimensions/).

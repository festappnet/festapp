# Jubilee 2025 web release readiness — 2026-08-30

## Canonical transition contract

- web-only tenant overlay `prod/jubileum2025` at
  `77093978881186b9d25cedd88a5a355e05a60d36` over canonical main
  `1ac1a4e04bd0694aeaba6bda1dcb89b3b6787657`;
- Flutter `3.47.2` and application version `0.19.93+473`;
- production origin `https://jubileum2025.festapp.net` and forced occasion
  `jm2025`;
- legacy source `https://lwfpdjxsdmkfyrzqbrlk.supabase.co`, organization `6`;
- pinned canonical target `https://api.festapp.net`, organization `9`, with
  stable Auth storage and refresh-or-reauth session transition;
- no iOS or Android release lane. Historical bundle/package identifiers are
  retained only as shared schema metadata and are owned by the CSM Ostrava
  mobile lane.

Organization `6→9` is the deterministic remap of the same Jubilee tenant. The
signed activation contract couples endpoint and organization ID and remains in
the legacy phase until the coordinated database freeze and final delta import.

## Production web and notification disposition

Cloudflare Pages serves the verified production build at
`https://jubileum2025.festapp.net`. Three consecutive deployment probes passed
the immutable bundle, legal-route, backend-activation and cache-revalidation
contracts. A clean browser start loaded the Jubilee occasion, selected the
legacy backend for organization `6`, and completed initialization without an
application error.

The Jubilee release does not initialize OneSignal. Its web and native
identifiers are empty, notification capability is fail-closed, and all web
bridge methods are inert when no web app ID is configured. Browser network
evidence recorded zero OneSignal requests.

The historical OneSignal dashboard naming/state was corrected on 2026-08-30
without changing any released client identity or subscriber namespace. Exact
provider-account evidence belongs to the private release repository rather
than this public operational document.

## Legacy Netlify retirement

Netlify deploy `6a9375953b8c718dd064bf09` reduced
`https://jubileum2025.netlify.app` to a compatibility boundary with no Edge
Functions. Root, event, form and sitemap paths return HTTP 301 to the identical
path and query at `jubileum2025.festapp.net`. The historical Flutter, Festapp
and `/push/` worker URLs return the same retirement worker so installed legacy
shells and any historical push worker unregister instead of continuing to run
against the old origin.

## Remaining shared cutover gate

No Jubilee-specific client release remains. Its only remaining step is the
shared production operation: maintenance freeze, final source delta import,
activation-document switch to the canonical backend, then retained-session and
read/write canaries. Jubilee must not be given a separate App Store, Google Play
or OneSignal release task.

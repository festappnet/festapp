# vstupenky.online public review readiness

## Actual state - 2026-10-27

Verified publisher Festapp; regional domain verification and dedicated-reviewer
OAuth succeeded in the real portal. Draft
`plugin_asdk_app_6ae002a14394819189521c68175a53d5` exists. Six tools scanned with
no findings; after deployment a rescan confirmed the restricted order schema.
Version 1.0.1 was uploaded and **submitted**. The portal list and version
detail both show **In review**; publication is **Not published**. See
[portal receipt](portal-status.json). Review is now pending with OpenAI.

## Deployed boundary

- MCP source: `bcacfc728a74cbd97b6afd6f007c8247116b90f2`; image
  `sha256:bdc4516832ee96af2ef232b99d861ab351ddc948c006c079cfd469836d610445`.
- Protected active regional client `festapp-chatgpt` explicitly selects
  `dataProfile: order-summary`; only its data profile changed. Native/private
  operator data remains available under independent scopes and consent.
- Six read tools, exact two read scopes, PKCE, no client secret or DCR.
- Buyer names, contacts, notes, answers, form fields and ticket/product free
  text are withheld from public orders; context omits user ID. Order identifiers
  remain pseudonymous. Event/template text is organizer-authored and subject
  to the published no-child-data/no-government-identifiers restriction.
- Exact symbol search follows bounded canonical pages, returns a no-data error
  when incomplete, and never labels a filtered first page a complete negative.
- Regional web/privacy: `0.20.429+933`, tenant
  `87468a4795855dd6eb9c7fac7f708536ac482cdf`, Pages `39c8bea7`.
  Three coherent production probes and current Czech privacy disclosure passed.

## Evidence

- 44 targeted remote/auth/wire and operation tests passed; modern and legacy
  text/structured output checks, arbitrary client IDs, private-field exclusion,
  exact-search continuation and retained operator DTO are covered.
- [Hosted public reviewer smoke](hosted-public-demo-evidence.json): all 13 live
  checks passed with ordinary demo login, first-party broker, real backend,
  scoped reads, withheld fields, refresh and immediate revocation.
- [Actual reviewer ChatGPT cases](chatgpt-public-reviewer-evidence.json): five
  positive and three negative scenarios in four conversational turns, including
  fresh ambiguity before selection. Related requests were grouped.
- Earlier failed ambiguity and retrieved injection tests remain historical
  operator-profile evidence in [earlier ChatGPT record](chatgpt-demo-evidence.json);
  they do not describe the new public projection.
- Two independent critics approved the restricted projection and configurable
  per-client architecture; final portal/package review precedes Submit.

## Review package

Version 1.0.1, exact three-file ZIP allowlist (plugin.json, mcp.json, owned logo).
No provisioning SQL, scripts, credentials or evidence is bundled. SHA256:
`533a4652c42efc4bd3cdc0f17d1d1b95b132e574c96d3f29bd8ea249ee39fb76`.

The [current walkthrough](walkthrough-public.json) is a verified 50-second
screenshot-based video from the actual reviewer conversation, not a continuous
login recording or independent proof of every call. Old immutable media remains
historical. Secure reviewer credentials belong only in the portal.

The portal currently requires final Terms/compliance/rights/no-money-transfer/
general-audience/no-under13-data declarations. The owner approved the restricted
public variant; do not attest to excluded data while running the operator
profile. The connector targets organizers, and the order fields carrying
registration/document/buyer data are withheld. No automatic public publication
is authorized merely by approval of review submission.

## Final portal receipt

Version 1.0.1, current P5 withholding expectation, all five positive/three
negative cases, Czechia scope, exact public video and secure current reviewer
steps were verified in the portal before Submit. Both critics approved the
actual final portal gates. No blocking findings were shown. Two advisory
automated assessments remained (category confirmation and privacy assessment);
the portal allowed submission and their limits were disclosed in Additional
Submission Context. All six declarations were completed for the owner-approved
restricted public variant. The portal then confirmed In review in both list
and version detail. No publication action was taken.

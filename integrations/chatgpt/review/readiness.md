# vstupenky.online public review readiness

## Current state - 2026-11-05

Public version **1.0.2 is In review / Not published**. The MCP configuration
is **Configured**, authentication is **Authorized**, and the latest scan
completed for all six tools with **zero findings**, including
`festapp_orders_report`. The previous Authorization required / Needs attention
state is resolved. Publication remains a separate action.

This is public plugin `plugin_asdk_app_6ae002a14394819189521c68175a53d5`;
the account's separate developer connector
`plugin_asdk_app_6adfeebe85a88191b9d0ba9339e381d6` is not the submitted listing.
See the [November 5 receipt](update-2026-11-05.json) for exact package hashes,
version identifiers, runtime and portal verification.

Version 1.0.2 contains the canonical October 29 ticket/V identity: full square
listing logos, compact composer symbols, light and dark exports, and colors
`#19243B` / `#80BDF2`. Descriptions, accepted publisher email, review cases,
endpoint, read-only scopes and data profile are unchanged. The original 1.0.1
artifact and historical receipt are retained.

The [post-cutover hosted test](hosted-public-demo-evidence-post-cutover-2026-11-05.json)
passed all 13 live checks on deployed source
`2b80ebb92f8ae37515e65fdebadb8751a8109089`: ordinary dedicated-reviewer login,
PKCE, exact event access, sales reports, order lookup, private-field exclusion,
scope/write denials, refresh and immediate revocation. This is native SDK
evidence, not a new conversational ChatGPT run. An independent critic approved
the prepared 1.0.2 branding, metadata and package with no blocking findings.

## Authorization recovery

The portal has two distinct connections. **Reconnect** on the MCP card selects
an account for metadata scans. The app-version authorization flag is completed
through **Connect MCP server** on a **Draft** version. A working scanner token
alone does not complete the app-version setup.

The review screen did not expose the draft-only authorization action. To fix
that state under the owner's instruction, version 1.0.1 was removed from the
review queue, the approved 1.0.2 package was uploaded, and the real app-version
OAuth flow was completed before resubmission. The dedicated reviewer consented
only to demo occasions 1072614 and 1072615 with the existing two read scopes.
The persisted version authorization flag became true; all six tools then
completed scanning. No customer events or whole-organizer access were granted.

One automated privacy-policy assessment was unavailable; the portal explicitly
allowed submission for additional review. This is not an automated privacy
approval and was not represented as one. Five positive and three negative
cases, secure reviewer credentials, and Czechia-only availability were retained.

## Historical submission - 2026-10-27

Verified publisher Festapp; regional domain verification and dedicated-reviewer
OAuth succeeded in the real portal. Draft
`plugin_asdk_app_6ae002a14394819189521c68175a53d5` exists. Six tools scanned with
no blocking findings; the two advisory metadata assessments are recorded below; after deployment a rescan confirmed the restricted order schema.
Version 1.0.1 was uploaded and **submitted**. The portal list and version
detail both show **In review**; publication is **Not published**. See
[portal receipt](portal-status.json). At that point, review was pending with OpenAI.

### Original deployed boundary

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

### Original evidence

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

### Original review package

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

### Original final portal receipt

Version 1.0.1, current P5 withholding expectation, all five positive/three
negative cases, Czechia scope, exact public video and secure current reviewer
steps were verified in the portal before Submit. Both critics approved the
actual final portal gates. No blocking findings were shown. Two advisory
automated assessments remained (category confirmation and privacy assessment);
the portal allowed submission and their limits were disclosed in Additional
Submission Context. All six declarations were completed for the owner-approved
restricted public variant. The portal then confirmed In review in both list
and version detail. No publication action was taken.

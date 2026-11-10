# Measurement merge readiness

Date: 2026-11-10
Status: execution in progress
Verification: standard, with the affected canonical CI mirror lanes

This plan supersedes the remaining-work section of the current-PR investigation.
The user authorized resolving the remaining architectural boundaries so PRs 785
and 786 can be merged. Production publication of these features is outside this
turn's scope; existing customer settings and tenant deployments are preserved.

## Decisions and current evidence

1. **785 uses the first-party host path for attribution.** The proposed raw-cookie
   replication lacks source expiry, destination scope and reliable revocation of
   global tag overrides. Remove that experimental extension rather than adding
   exceptions around it. Keep the existing isolated Unit runtime as its existing
   independent destination. New CMS defaults use the host path; old content keeps
   its mode. Do not claim cross-site identity/session continuity for Unit mode.
2. **Provide a real GTM preset.** A task-owned workspace in the existing explicitly
   nonproduction Festapp container is used to obtain authentic native schemas
   and validate import. Never publish it. Default tags are paused, merchant IDs
   are unset, and Ads data terms/account settings remain a merchant operation.
   GA4/Ads use native tags; Meta sends public ecommerce only. Every trigger is
   scoped to Festapp host events and every destination has explicit consent gates.
3. **786 needs a live scoped source, not a one-shot boolean.** The existing
   connectMeasurementConsent API already uses source.read(scope), subscribe and
   processingRevision. Make its validation and provider lifecycle one owner,
   usable by both iframe bindings and links. A new global source registration
   supplies revision-aware choice records. Google Consent Mode alone cannot
   prove a visitor record's revision, so standalone links do not infer coverage
   from it. Existing automatic embed behavior remains its bounded compatibility
   boundary when no global source was configured; an explicitly disconnected or
   failed global source never falls back to automatic grants.
4. **One lifetime authority.** FormMeasurementSession already carries leaseId and
   expiresAt and checks them on every event. Use this contract for linked consent.
   Fix policy renewal so it never extends the transport beyond source expiry.
   Add monotonic message sequence, exact peer/origin/scope, a 60-second renewable
   lease, source-change notifications and bounded total visit duration.

## Target invariants

- No host cookie identity reader, hostIdentity wire field, cookie copying,
  manufactured identity retention or global client_id fallback remains in 785.
- Host and Unit destinations remain exclusive; old saved embeds are not migrated.
- GTM preset imports into the isolated test workspace without overwriting existing
  workspaces; all shipped tags are paused and no real account IDs are included.
- Only source records whose stored processingRevision matches the requested scope
  can authorize linked choice. The website adapter must not echo the request's
  revision as invented evidence. Unknown/stale records produce local fallback.
- Source withdrawal is propagated while connected. Source closure, replacement,
  navigation, error or lease expiry removes the imported grant; local explicit
  choices take precedence and disconnect the remote source.
- Imported purposes stay in the existing Klaro adapter model. No imported choice
  is persisted and no store method is replaced. Heartbeats preserve a local draft.
- Replayed/out-of-order messages and delayed timers cannot restore an old grant.
- Session and runtime transport expiry cannot exceed the source lease even when
  policy renews. Missing source permits only the existing denied-state behavior.

## Waves

### 1. Narrow and complete PR 785

Restore the experimental web/Worker identity paths to canonical main. Preserve
CMS defaults and their now-collected regression tests. Remove obsolete identity
and linker-forwarding tests/docs; keep only supported arrival URL behavior.
Add the GTM preset, canonical generation/validation and setup guide. Obtain native
GA4/Ads/User-Provided Data structure from the isolated test workspace, sanitize
IDs, and validate a real import. Never turn on DOM contact detection or accept
account terms. Guide uses the bounded user_data field and explicit consent.

Exit: first-party delivery and setup are complete; unsupported identity code and
claims are absent, and temporary CMS packaging leaves release ZIPs unchanged.

### 2. Shared revision-aware source

Add a small owner for scope validation, current-record projection, provider
registration, notifications and disconnect. Move the existing explicit iframe
adapter onto it. Expose one global source registration in FestappEmbed for links
and default iframe bindings. Retired callbacks are inert; a configured source
failure or disconnect denies instead of restoring an automatic grant.

Exit: both transports consume the same source contract and no second explicit
Consent Mode reader is needed for links.

### 3. Renewable linked choice and canonical expiry

Replace the one-shot request with a bounded live channel. Track exact popup,
nonce, normalized scope, sequence, provider generation, lease and visit deadline.
Update or terminate on source changes; cleanup on closure/navigation/disposal.
Child initial wait stays 1.5 seconds and opener remains detached. Carry the lease
through CMP into FormMeasurementSession; clamp all transport renewals. Preserve
the floating settings UX, explicit local persistence, draft cancellation and
another tab's newer local choice.

Exit: regression tests reproduce and then reject stale scope, lost connection,
revocation, suspended timers, out-of-order messages and expired grant renewal.

### 4. Verify and update the existing PRs

Run targeted real-Klaro and source/session regressions, then canonical web-startup
and Wix/CMS lanes on frozen inputs. Delegate browser operations to Terra. Test
the actual GTM import only in the new nonproduction workspace, with paused tags;
clean only task-owned draft artifacts after exporting proof.

Fetch main and both PR heads immediately before each normal fast-forward update;
reconcile intervening commits and rerun affected checks. Rewrite PR descriptions
around final behavior and measured evidence. Do not approve speculative identity
claims, add a parallel PR, silently merge or deploy these changes.

## Deletion ledger

| Artifact | Action and proof |
| --- | --- |
| readHostMeasurementIdentity / measurementHostIdentity / hostIdentity | Remove definitions and callers from 785; scoped search and transport tests prove absence. |
| Cookie-copy, cookieAge, setClientId and identity polling | Remove from 785, including tests that endorse retained identity after withdrawal. |
| Experimental direct linker forwarding/cache | Restore canonical supported arrival behavior; no iframe attribution guarantee. |
| One-shot link response and long-lived import timer | Replace with live leased channel and canonical session expiry. |
| readExplicitHostConsent and unknownAsNull link reader | Remove; links require revision-aware source records. |
| Duplicate inline explicit source validation | Move to shared source owner; preserve the existing iframe public contract. |
| Prototype consent cookies/store patches | Remain removed; retire any historical prototype metadata before binding. |

## Rollback and limits

No database migration or customer-setting write is needed. Code changes use normal
commits on the existing contributor branches. A deployment remains separately
controlled by canonical main CI and tenant gates. A source that cannot supply a
revision-aware visitor record retains local consent fallback; no unsafe automatic
coverage is synthesized. The GTM preset still needs merchant-specific IDs, terms
and preview before that merchant publishes it; test import is not an account's
real conversion-attribution proof.

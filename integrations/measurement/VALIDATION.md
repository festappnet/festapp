# Current preset validation - issue #804, 2026-11-11

Implementation base: main `32032baa7` with #803 consent changes and #806 order
reads preserved. The old four-tag receipt is retained in `validation/2026-11-10.md`;
it is not evidence for this replacement.

## Exact artifacts

- Canonical `festapp-host-gtm.json` SHA-256: `17c8a6af2211ddf12012f60ea16e87666ebc92e3605b240a632819790fbaea4e`.
- Pinned Meta Pixel: 2.0.9, commit `08b9bbba509d6f10f6ad2bd39207ed814e96cbbe`.
- Pristine upstream template SHA-256: `cb1a985310c1f568627ad95150655934077a4a1757acc7832f27376231ee80af`.
- Private actual GTM workspace export SHA-256: `7d47714004bda3a6ee281831398f6012f3730574ccde95caedeb0f7ef46228ce`.
  That raw export stays in the operator's Downloads; it is not committed because
  it contains real account/container identity. No account identifiers are bundled
  in the canonical preset or sanitized gallery template record.

## Executed evidence

The original preset failed the new Google-consent regression (`NEEDED` versus
`NOT_NEEDED`) before implementation. Final targeted web tests passed 25/25,
including twelve preset/projection/actual-upstream-template tests and the existing
host analytics/shared contract tests. Help-page tests passed 3/3. Generator parity
and diff whitespace checks passed.

The Meta tests execute pristine pinned sandboxed JavaScript with modeled public
GTM/SDK I/O. They cover projected purchase/zero-valued lead, customer matching,
SDK absence/queueing, explicit CAPI opt-out and the optional external parameter
builder dependency. They do not execute Meta's network transport or Google
native tag internals.

The operator created a separate, task-owned workspace in the existing explicitly
nonproduction GTM container. Both pre-existing workspaces were left untouched.
The official Meta template was installed from the actual gallery and exported;
its genuine owner/repository/version/signature/update identity are retained.
Executable JavaScript and permissions match pinned upstream; parameter JSON is
semantically equal after GTM serialization. A temporary native User-Provided Data
variable proved `awec` / `mode=MANUAL` / `email` / `phone_number` export fields.
The probe was removed before final import.

The exact canonical artifact above was imported using **Merge** and **Rename
conflicting tags, triggers and variables**. Import succeeded. Final export proves:

- 18/18 tags paused, 11 triggers, 28 variables, one folder, one Meta template;
- no duplicate gallery template and the same genuine gallery reference;
- every tag/variable parameter value preserved after ID remapping;
- every firing-trigger association and embedded/event/subtype filter preserved;
- native/manual user-data references, Google `NOT_NEEDED`, and Meta `ad_storage`;
- CAPI opt-in false, automatic ecommerce inheritance false and explicit matching
  inputs only on the two Meta conversion tags.

The actual GTM editor interpreted GA4 purchase and lead `user_data` through the
native manual variable, ecommerce on purchase, and event-scoped lead fields.
The manual variable editor showed both GA4 and both Ads consumers. Ads purchase
showed its event-level user_data mapping, monetary/transaction/ID constants,
built-in Google checks and **No additional consent required**. Registration was
bound to the free-registration subtype trigger. Meta Purchase displayed the
standard event, matching fields, public-property variable and ad_storage check.
The CAPI authorization checkbox remained unchecked; no terms were accepted.

## Limits and retained state

No GTM version was published, no tag was unpaused, no account/data capability
or customer-data policy was changed, and no conversion traffic was sent by this
task. Preview traffic, consent-network behavior and live destination delivery
were not tested while all tags stayed paused. Those remain merchant activation
checks with real destinations and an approved CMP/SDK setup.

The task browser tab/session was closed. The isolated nonproduction workspace
is retained as import evidence. This proves importability, native editor
interpretation and deterministic projection behavior; it does not prove account
eligibility, reporting, campaign attribution or Meta/Google network delivery.

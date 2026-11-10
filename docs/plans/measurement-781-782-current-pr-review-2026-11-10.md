# Measurement 781/782: current PR review and implementation

Date: 2026-11-10
Status: targeted corrections prepared; neither complete feature approved for release
Verification: standard for consent, identity and public messaging boundaries

## Current sources

- Main `c611f5114591f45fd9c6cecc5c4531057900e92f`.
- Issue 781 / PR 785: `c11b203aa0e328d4e474ec590d6d57d93316f26b`.
- Issue 782 / PR 786: `f8cf1542f5954096cb8515f0aab41c23905538b5`.

Use the existing contributor PRs. Do not publish a competing implementation or
merge them based on the older experimental heads. PR 786's latest floating
settings-button UX and independent fixes for removed-source grants and cross-tab
expiry are preserved. The old source-notice UI is superseded.

## Verified defects and corrections

### PR 786: lifetime and handoff deadline

Both regressions fail against an unmodified archive of the current `f8cf1542f`
source with the new regression tests:

```sh
pnpm --dir web_client exec node --test \
  --test-name-pattern='host rejects an expired|a later visit without' \
  tests/forms/form_consent_link.test.js tests/forms/form_measurement_cmp.test.js
```

- A host timer is delayed or suspended: the tracked popup remains usable after
  60 seconds because only a timer handle is stored. Store an absolute deadline
  and reject expired requests directly in the handler. Do not rely on cleanup.
- Session cookies are shared across visits/tabs. The prototype restores the
  remote grant in a later openerless visit within 24 hours. Keep remote choice
  only in the current controller's in-memory Klaro model, scoped to its current
  organization/Unit/processing revision. A new visit needs a new handoff or the
  normal local notice.

The existing consent adapter owns the pinned Klaro model transition; no store
method is replaced. The import marker owns lifetime only, not another copy of
effective purposes. Explicit local saves retain ordinary 180-day persistence.
Expiry adopts a newer local choice rather than deleting another tab's cookie.
Draft deselection still revokes immediately; Escape restores the choice and
focus without writing cookies. Older prototype import cookies, including invalid
source metadata, are retired before grant publication.

The canonical browser fixture now tests the same contract: initial import has no
bar and a visible floating settings button, no cookie is created, another tab or
reload asks locally, and an explicit local refusal persists on later reload.
The earlier fixture timeout was an assertion that the imported state survived
reload, which contradicts the corrected visit-only lifetime.

### PR 785: linker survives frame recreation

The original runtime re-reads `_gl` at every activate(), after ready already
removed it from the address bar. A later grant following frame recreation loses
the original linker. The new regression fails before the fix and passes after:

```sh
pnpm --dir web_client exec node --test --test-name-pattern='entry linker survives' \
  tests/forms/form_measurement_runtime.test.js
```

Capture validated entry signals once at the existing runtime owner. Keep them
through frame recreation only within the original origin, organization, Unit,
form and processing revision. Clear them irreversibly on scope change. Both
purposes are still required before forwarding `_gl`.

The new WordPress and Joomla default tests are also wired into the canonical
`automation/test_embed_adapters.sh` fixture gate, alongside existing renderers.
Tests package temporary copies; reviewed ZIPs are not rewritten. New CMS embeds
select host while old saved configurations retain unit. Joomla's Form API is
stubbed in that regression: official 5.4.10/6.1.4 source confirms bound-value
semantics, but a real CMS integration is still a separate proof.

## Architectural findings still blocking approval

### PR 785: raw identity replication is not a canonical contract

`host_measurement.js` exports all matching website GA cookies under an existing
purpose grant, including grants from explicit adapters with bridge opt-in off.
There is no destination-bound identity scope or processing-revision change for
that new disclosure. The runtime assigns GA copies two years without knowing
the source cookie's expiry. Cookie deletion also does not remove a global
`gtag('set', {client_id})` override; the prototype explicitly keeps it after
withdrawal. A later successful cookie write for B can leave fallback A active.

Recommended separation: keep the new-CMS host defaults and first-party event
transport as one coherent deliverable, supply an importable GTM setup, and keep
identity continuity behind a separately reviewed destination/consent/retention/
revocation contract. Do not patch this by always setting client_id: that would
make the unresettable override apply to more visitors. Matching cid/sid in a
captured hit does not alone prove source attribution or withdrawal correctness.

### PR 786: source withdrawal and processing coverage

A one-shot response cannot synchronize a later withdrawal on the website.
Visit-only lifetime fixes cross-visit reuse, but is not live revocation. Design
a bounded live source lease with updates and fail-closed disconnection, or make
an explicit product decision about another permitted contract before release.

The request includes a processing revision; current global Consent Mode does not
establish that the visitor's original choice covered it. Re-confirming an
organizer toggle alone is not evidence of a new visitor choice. Specify a
revision-aware source/coverage contract and organizer confirmation record; share
that owner with the existing embed bridge instead of building a second consent
authority. Unknown coverage must retain the local-choice fallback.

## Primary sources and evidence limits

- [Google gtag reference](https://developers.google.com/tag-platform/gtagjs/reference)
  documents querying client_id/session_id, not replicating private cookies.
- [Google cross-domain guide](https://developers.google.com/tag-platform/devguides/cross-domain)
  describes related websites; arbitrary iframe attribution needs separate proof.
- [CHIPS](https://developer.mozilla.org/en-US/docs/Web/Privacy/Guides/Third-party_cookies/Partitioned_cookies)
  partitions state by top-level site instead of sharing the host cookie jar.
- [Safari 26.2](https://webkit.org/blog/17640/webkit-features-for-safari-26-2/)
  documents changes since the older versions referenced in the issue.
- [postMessage](https://developer.mozilla.org/en-US/docs/Web/API/Window/postMessage)
  and [COOP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Opener-Policy)
  define peer checks and opener constraints.
- [Joomla Form 5.4.10](https://github.com/joomla/joomla-cms/blob/5.4.10/libraries/src/Form/Form.php#L476-L485)
  and [6.1.4](https://github.com/joomla/joomla-cms/blob/6.1.4/libraries/src/Form/Form.php#L476-L485)
  read bound Registry values rather than XML defaults.

Node regressions use real Klaro in JSDOM, including shared cookie jars. Real
browser contract checks use isolated local fixtures, no customer orders or
conversion events. They do not prove attribution in real organizer accounts or
establish legal sufficiency of a notice. Keep both issues open and do not deploy
the complete experimental features based on these targeted corrections.

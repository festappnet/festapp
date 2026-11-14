# CMS consent completion - implementation evidence

The selected rollout is vstupenky.online (`festapptickets`). The user also
included the existing Wix widget and HTML/Webnode generators. WordPress and
Joomla package sources are prepared; publication to their public catalogues is
outside this rollout. No other tenant or marketplace listing is included.

## Ownership and contract

- PostgreSQL owns each Unit/website binding, manager authorization, normalized
  provider configuration, semantic notice revision, optimistic version and
  confirmation. Disable preserves a versioned tombstone. The forward migration
  is `20261114170000_website_consent_bindings.sql`; historical migrations remain
  unchanged.
- The Unit settings screen loads, saves, confirms, exports and disables that
  binding. Unsaved settings, stale versions, missing approval or unavailable
  server state cannot produce a usable export. Origin and Unit scope come from
  the server. A persisted ExpansionTile scroll-state collision found in the
  actual release UI was fixed and has a widget regression test.
- Public policy exposes only binding ID/version/origin/effective state.
  Existing host adapters and the local consent controller enforce the binding,
  revocation and local choice. No second consent engine or public configuration
  endpoint was introduced.
- WordPress/Joomla import one JSON document with an explicit enable control.
  Provider editors, scope fields and notice-revision editors are absent. Shared
  PHP validates the envelope only. Helpers affect their own embeds and marked
  links, with explicit conflicts failing closed.
- Wix uses the same import and helper registry. Its native adapter reads the
  current public consentPolicyManager API, validates its saved date and declared
  age/cutoff, and rechecks withdrawal. HTML/Webnode reuse the existing generator
  and the same export. Make/API connectors do not carry browser consent.

## Verification

Targeted checks passed against the isolated implementation worktree:

- Two actual PostgreSQL rollback suites and three two-session/reapplication
  cases: authorization, scope, effective state, stale writes, disable and safe
  repeat application. The disposable backend also replayed the real baseline
  and forward history.
- 483 JavaScript consent/runtime/helper tests passed. Wix: 53 passed, four
  existing optional environment cases skipped; the 0.1.4 build passed.
- 47 collected Flutter widget cases passed with Flutter 3.50 and concurrency 1,
  including saved-setting gating, confirmation/export/disable, unavailable and
  stale states, provider fields, website lifecycle and visible export text.
- PHP renderer/envelope/mixed-version-load/default contracts passed. Real
  installed WordPress current/minimum and Joomla 5/6 tested both product
  packages, persistence, native validation, escaping and helper ownership.
- The actual Flutter release UI saved and copied a Unit 2 export. That exact
  payload was entered through WordPress administration and used by a real
  public form on the disposable backend. Grant, refusal, disable and stale
  export denial passed. Light screenshots also verified Wix fields and the
  corrected visible JSON export. Task-only browser targets were removed.
- The existing live Wix development site verified native default/saved policy
  behavior and fresh API denial after deletion and cross-tab withdrawal of the
  task's own consent cookie. No site publication, order or account changes were
  made for this probe.
- Canonical CI inventory ownership passed; 54 CI contract/selection/scheduler/
  release-gate tests passed. Hosted Wix compatibility now owns the complete
  disposable CMS/backend/browser command, its prerequisites and resource lease.
- The complete owner passed nine cases: WordPress current in Chromium, Firefox
  and WebKit; WordPress minimum, Joomla 5/6, Wix and generated HTML in Chromium;
  and Joomla 5 with COOP retained. Positive cases covered grant/refusal, source
  withdrawal, disable and stale export denial. Wix additionally covered iframe
  local choice and lease renewal. This is the executed matrix, not every
  platform/provider/browser cross-product.

Before publication, the implementation was rebased onto the intervening order
terminology change. Its test inventory additions were preserved alongside the
six new consent cases. All 47 targeted widget cases, 54 CI contracts, eight
forward-owner tests, canonical source generation and the two actual database
binding/source-parity suites passed after that reconciliation. The shared
generation was stamped as `0.20.613+1140`; eight version tests passed. The browser
matrix preceded only the generation stamp, whitespace cleanup and unrelated
upstream terminology changes; hosted CI runs the owner again on the exact main.

The normal reproducible browser owner is
`python3 automation/testing/cms_consent_fixture.py`. It creates and tears down
its own backend/CMS resources, refuses occupied ports and records source hashes.
The public form, SQL RPCs, CMS installations, Wix element and HTML generator are
real. CMP APIs and Wix Site mode are modeled at their documented boundaries;
this is explicitly separate from the native Wix evidence above. Positive Joomla
proxy cases remove COOP only in the test transport; a separate negative case
retains the installed COOP header and requires local-consent fallback.

## Publication boundary

Dependabot PRs #859-#863 were squash merged after their successful checks.
Selected renderer code from #856/#857 was integrated into this implementation;
their obsolete provider configuration was not merged. Production migration,
exact-main CI gate, tenant overlay, direct web deployment and hosted Wix asset
verification are recorded separately by the release owner after execution.
An implementation receipt or merged source alone is not deployment evidence.

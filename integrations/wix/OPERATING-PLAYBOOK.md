# Wix integration operating playbook

This is the reusable procedure and experiment log for native Wix registration,
qualification and publication. Update it when an experiment changes a conclusion.
Keep observations, hypotheses and completed effects distinct. The current
machine-readable state is in [the continuation receipt](evidence/continuation-20261101.json).

Current conclusion: the original premature error was our wall-clock deadline,
not proof of a vendor-wide SDK failure. The visible-time fix passes real native
authentication on all three QA platforms. Publication and purchases are separate
effects and must not be inferred from that result.

## Authority and scope

- App identity: [wix-app.json](wix-app.json). Native widget tag:
  `vstupenky-online-form`; extension identity is in the registration receipt.
- Public assets: existing Cloudflare Pages project `festapp-wix`, production
  branch `main`, stable `https://festapp-wix.pages.dev`.
- Checkout authority: `https://vstupenky.online`; backend:
  `https://api.festapp.net`. Selected tenant is `festapptickets`, canonical
  generation 1, organization 3. This does not authorize other tenants.
- Checkout, inventory and money remain in the canonical Festapp services.
  Wix provenance is not customer-acquisition evidence or a source of service fees.
- Keep app secrets, access tokens, signed contexts, buyer data and private
  contracts out of command output, screenshots and committed evidence.

## Start from the actual state

1. Read repository agent rules, the current continuation receipt and only the
   evidence needed for the failing stage. Do not repeat the full historical setup.
2. Check the existing Wix support thread before repeating any vendor step.
   Current thread: `1a18198a75444077`, case `065800261`.
3. Record native release, installed version when exposed, source URL, actual
   executed asset hash, site type, browser/profile and backend activation.
4. Verify the selected tenant before backend diagnostics. Use the project
   backend-access skill and explicit read-only transactions, not old cloud projects.
5. Preserve the previous immutable assets and native configuration before edits.
   Pre-existing missing QA forms are not new failures caused by a deployment.

## Browser and account handling

Browser profiles do not share logins. BrowserOS neo lacking a Wix login says
nothing about the user's main Chrome. The user explicitly authorized main
Chrome through Panerelay for this task.

For that session, use the installed Panerelay skill and current core CLI guide:

```sh
agent-browser skills get core
agent-browser --provider panerelay --session wix-<task> snapshot -i
```

Open new background tabs, mute owned media, use fresh snapshot refs and preserve
the user's tabs. Do not use launch/profile flags against Panerelay or clear the
whole profile's cache/cookies. A selected target drifted to a user tab during one live session. A separate URL
check followed by a raw reload is not atomic. Check the owned tab ID and guard
the hostname/path inside the same page mutation; abort on a mismatch. Fresh refs
are required for native controls. Close the exact participant when finished;
`close --all` is inappropriate. Browser interaction belongs to the designated
Terra browser operator; routine deployment belongs to the deployment operator.

A clean local headless browser can be a separate public-runtime control to
distinguish browser/profile effects. It must have a new isolated session and
explicit empty configuration, no user credentials, no paid provider, and the
same read-only request fences. It is not a way to bypass account authorization.

The repeatable current-project probe uses only such a fresh local browser:

```sh
python3 integrations/wix/scripts/probe-native-auth.py --site harmony --bundle integrations/wix/dist/widget.js --form country_bal_vetrkovice
```

Repeat with `--site studio` and `--site editor`. It verifies the actual served
bundle hash, automatic native proof POST and frame/link context presence. The
temporary element is mounted outside the Wix-managed subtree: React reconciliation
removed an earlier sibling clone even after the proof succeeded. The probe is
for the reviewed widget, not a general sandbox for untrusted JavaScript. It blocks
checkout documents and known REST/Auth/order/hold routes; the CLI does not enforce
an arbitrary-function allowlist. An exact no-option route does pass through alone,
but a broad abort also wins over an overlapping exact rule in either order.
For deployment readback, add `--live`: it leaves the registered script response
untouched and requires it to match the expected bundle. Do not confuse a passing
source-override experiment with a passing deployed-version check.

## Native app registration and versioning

The extension is `CUSTOM_ELEMENT_WIDGET`, script type `COMMON_JS`, with the
assigned tag and public script/settings URLs. The UI's frontend SDK checkbox
corresponds to the native `@wix/site-site` dependency v1. Record both UI and
configuration readback; a checkbox alone does not prove token delivery.

There are separate publication effects:

| Action | Effect to verify |
| --- | --- |
| Save extension/pricing/profile | Saved draft, not necessarily the installed version |
| Test App / Update App | Installation/update confirmation, not proof a widget's script URL changed |
| Publish a QA site | Published page/model, not App Market publication |
| Release minor version | Dialog says changes push immediately to installed sites |
| Release major version | Dialog says existing users must manually update |
| Submit and Publish | Actual App Market review, with automatic listing if approved |

Version releases cannot simply be undone from history. Do not release versions
just to clear a cache. A controlled manual-update major test is appropriate only
with a defined owned-site target, restoration plan and no new fee/legal scope.

Observed configuration propagation: existing widget instances retained their
previous script URL through draft edits, Test App, app update and site publish.
A fresh instance after native 2.0 release finally loaded the diagnostic URL.
Check the *actual Script response* or DOM script URL, not just a saved dashboard
field or update toast. Put a temporary fresh widget on its own QA page to avoid
two scripts defining the same custom-element tag on one page. Record the page ID
and remove only that temporary page afterwards.

## Read-only native authentication probe

The real endpoint is declared in `src/config.js`:

```text
https://api.festapp.net/functions/v1/wix-checkout-context
```

Do not guess `/wix-proof`, `/proof` or a regional host. Expected non-mutating
handler controls are OPTIONS 200, GET 405 and POST `{}` 400. These prove reachability
and rejection/CORS behavior, not successful authenticated provenance.

For an actual authenticated probe:

1. Use a known existing open public form in the selected organization. The
   historical `wix-qa-20261025` slug does not exist in production. Existing demo
   forms require an authenticated organization user; they are not anonymous
   reviewer sandboxes. Do not present a real sales form as a test-purchase sandbox.
2. Fence orders, holds, payments and other mutation routes. For a proof-only
   browser experiment, abort checkout documents/helpers and backend REST/Auth;
   allow only the proof route required by this experiment. Do not submit a form.
3. Verify the hash of the script that actually executed. A separate no-store
   fetch matching a new hash does not prove an already-loaded page ran it.
   Stable assets have a 300-second cache. Refresh only the owned target/resource.
4. A failed form leaves `mode=Unavailable`. Merely changing `form-url` afterwards
   does not restart the Site-mode/proof sequence. Reconnect or clone the owned
   DOM element with the valid URL, then restore through page reload. Do not save
   runtime probe changes into native settings.
5. Record mode, whether `originForm` was assigned, listener invocation count if
   instrumented, new proof request method/status, context presence, and whether
   iframe/direct-link URLs contain a context parameter. Never print the context.
6. Successful qualification requires the real SDK request and response. Manually
   calling `accessTokenListener` with a token tests a seam and is not native delivery.

The Oct 28 successful isolated Harmony probe fulfilled the registered script URL
with the actual bundle through `network route ... --body <JavaScript>`, then
mounted a fresh valid-form clone. It did not manually inject the token. Its real
POST succeeded and SQL verified the returned signature. This is a useful control
to reproduce, not a reason to assume the current browser behaves identically.
Body fulfillment worked in that isolated CLI execution; support/MIME under a
different provider must be tested rather than inferred from abbreviated help.

## Locate the failure before changing code

| Observation | Meaning and next check |
| --- | --- |
| Site-mode call rejects | Host/client binding stage; not a backend CORS finding |
| Site mode, no new proof OPTIONS/POST | SDK authentication or another stage before `fetch` |
| Actual new OPTIONS fails | Compare requested headers with allowed headers; include `x-wix-linguist` |
| Proof POST 4xx | Read the bounded provider error and verify app/instance/form scope |
| Proof POST 200, no frame | Check response shape, expiry and widget generation/state |
| Frame/link have context | Provenance mount works; still not a purchase/refund test |

Start network capture before the action and distinguish manual control requests
from subsequent SDK requests. Reusing an earlier manual OPTIONS as evidence of
the SDK's preflight caused a wrong CORS hypothesis on Nov 1.

The installed Site SDK's `getAuthHeaders()` waits for a provider once
`getAccessTokenInjector()` has been created. This can remain pending before any
HTTP request. The widget's generic Czech error was its own 12-second timeout,
not a vendor HTTP error response. Do not call the provider permanently absent
from a snapshot taken at that deadline: it later arrived in the same browser.

The native renderer's passive effect calls the listener after `whenDefined(tag)`
if its `getAppToken` prop and DOM ref are available. A clean visible browser
called it after about 4.7 seconds and completed the proof after 5.6 seconds.
The owned main-Chrome tab was hidden and could remain unhydrated beyond 60 seconds.
The distinction was established with the same script and native site, without
changing browser privacy settings or manually supplying a token.

The fix counts a 60-second **visible-time** budget, pausing it while the document
is hidden and retaining the remaining budget across visibility changes. Fast
native delivery still completes immediately. Expiry aborts the request; later
tokens cannot reopen an expired attempt. No unsigned fallback or automatic retry
was added. Regression coverage advances fake time through delayed injection,
hidden startup, repeated hide/show transitions and expiry. Clean visible native
verification also passed; hidden main Chrome remained loading rather than
showing a false error after more than 75 seconds.

The SDK also has a script-identity path through `wixEmbedsAPI` and
`wixTagManager.getAppId()`. Module initialization timing can matter. Capture
authentication during script execution, but do not spoof `document.currentScript`,
read private viewer-model tokens, or add an unsigned fallback to make a test pass.

Official reference: [identify an app instance in a self-managed site widget](https://dev.wix.com/docs/build-apps/develop-your-app/develop-a-self-managed-app/supported-extensions/site-extensions/site-widgets-and-plugins/identify-the-app-instance-in-a-self-managed-site-widget).
The documented full module-level client plus constructor listener was used by
the auth-only diagnostic; it records only booleans/counters/statuses.

## Experiment ledger

| Case | Actual result | Conclusion limit |
| --- | --- | --- |
| Oct 28, isolated Harmony, reviewed bundle override | Automatic real SDK proof succeeded; SQL signature verified | Controlled source override; not every editor/profile |
| Nov 1, main Chrome, Studio dev site, normal candidates | Site mode, no authenticated proof, timeout | Not established as CORS or complete root cause |
| Nov 1, fresh Studio widget, native diagnostic 2.0 | Exact diagnostic loaded, Site, listener count 0, timeout | Literal native example failed on this installation |
| Nov 1, main Chrome, ordinary Harmony, corrected bundle | Reconnect and fresh clone both timed out before proof | Falsifies the hypothesis that only dev-site origins fail |
| Clean current local browser, same route-fulfilled candidate | Native listener invoked; real proof POST 200 | Falsifies a universal Wix failure |
| Main Chrome, exact same route fulfillment | Deadline expired; listener later arrived | Code bytes/MIME alone do not explain the problem |
| Native renderer caller inspection | Provider/ref eventually present in both; effect calls after definition | Do not ship private React/TagManager workarounds |
| Main Chrome hidden, 60-second wall-clock experiment | Still timed out before native injection | Merely increasing the fixed deadline is insufficient |
| Fixed visible-time budget, main Chrome hidden | Site/loading retained after 75 seconds; no false error | Does not claim a foreground main-Chrome proof was observed |
| Same fixed bundle, clean visible browser | Automatic real proof 200; frame/link retain context | Confirms the supported native SDK path without injection |

Actual App Installations listed ordinary Harmony and an uninstalled ordinary
site, but omitted the owned Studio/Editor development sites. Inventory is not
complete for development sites. `mode=Site` alone does not establish which
installation/authentication environment is in use.

## Build, deploy and restore

Use pnpm 11.24.0. The canonical affected compatibility batch is:

```sh
python3 automation/ci/run.py step wix-contract
```

The final Nov 1 visible-time fix run passed 46 Wix and 54 shared checkout tests, with
four database tests skipped because no disposable database URL was supplied.
Unchanged SQL had separate historical PostgreSQL evidence. Never report skipped
database tests as passing or unit/manual token injection as live native success.

Build/package only final inputs and preserve predecessors first: the existing
package command reuses the versioned ZIP filename. Keep content-addressed sealed
copies before rebuilding. Record source SHA, ZIP hash, manifest hash and every
public member hash. ZIP container metadata can change its hash while all asset
bytes are identical; substitution is admissible only after independent complete
member/path/manifest and reviewed-preview comparisons, with that decision recorded.

Deploy only the verified immutable staging directory to the existing Pages
project, after checking authenticated account and activation. Verify unique and
stable URLs, all public asset bytes, MIME types, CORS and cache/security headers.
Retain the previous deployment for immediate restoration. A failed live trial
must be rolled back before open-ended investigation.

CLI requests to the backend encountered Cloudflare Error 1010. The real Wix
browser reached the correct handler successfully. Do not change server CORS or
claim an outage from that CLI/WAF response; measure the actual browser boundary.

For source publication, fetch the authoritative target and check branch rules
before pushing. This repository reported a required-PR rule after one accepted
direct push. Do not repeat that bypass; use the PR workflow and current base.

## Billing and App Market gates

Keep the four different states separate: signed addendum, native external
billing approval, BI-ingestion confirmation, and local financial-dispatch enablement.
Only actual service/platform fees are reportable; ticket face value and organizer
funds are excluded. Rates are individually agreed, with no invented default.

The one qualification-only zero event was explicitly approved, sent and confirmed
by Wix. Inspect its durable shared journal with:

```sh
pnpm --dir integrations/wix run billing:qualify inspect
```

Do not resend it, remove the fence, switch worktrees to reset it, or create fake
financial source rows. Real dispatch requires actual settlement/acquisition
evidence and its separate activation record. Follow [DELIVERY.md](billing/DELIVERY.md).

Before App Market submission, complete the real editor/lifecycle and store/reviewer
access gates. Run `release:check` on references to actual receipts; its string/
boolean declarations do not independently establish that evidence. A zero-blocker
native checklist is not proof of a functioning authenticated checkout. Restore
temporary pages, script URL, native version and owned browser participants before
handoff, and record any installed-version field that Wix does not expose.

## Public instructions and canonical identity

The organizer-facing setup guide is published at
https://wix-guide.festapp-wix.pages.dev/help. It must state the actual App Market
availability; a working public guide is not approval of the app itself. Keep
customer instructions separate from this internal operational history. Never
publish private mailbox/thread IDs, database access instructions or token traces
as customer help.

A separate sanitized technical walkthrough is published at
https://wix-guide.festapp-wix.pages.dev/integration-guide. Keep live app IDs,
private support history and backend administrative access in the repository's
operational records rather than that public walkthrough.

The canonical regional identity is owned by
`assets/brand/vstupenky-online/README.md`: wide ticket/V without a head, navy/blue,
outlined Roboto lettering. Copy the header/icon SVGs from that source during the
Wix build. Render the 1000px native app PNG directly from the approved square SVG
using the existing vector renderer. Do not generate an alternative logo or
rebuild lettering by hand. Public contact copy uses `info@vstupenky.online`.

Panerelay's direct file upload returned a CDP `Not allowed` error for the actual
file input. The supported Wix Media Manager **Link (URL)** importer worked with
the public immutable canonical PNG URL. Save the app icon, cold-read its CDN
original and compare the exact hash. Update App Profile is distinct from releasing
an app component or submitting to the Marketplace. Do not change shared developer
company branding or gallery screenshots as an incidental side effect.

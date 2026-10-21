# Web security hardening - execution result 2026-10-18

Status: implementation prepared for an explicitly authorized draft PR; GitHub protections partially activated; **production rollout and CSP enforcement incomplete**. Required repository gates still fail on unchanged main SQL/Flutter/infrastructure contracts. The user subsequently granted an exception for draft PR publication with those failures disclosed. This exception does not authorize merging or deployment with failed gates. No production deployment was attempted.

## Source and live identity

- Isolated checkout: `/Users/miakh/source/festapp-web-security`.
- Local branch: `security/web-hardening-20261018`. The initial handoff left changes uncommitted because CONTRIBUTING.md requires a passing full suite before every commit. The user subsequently explicitly authorized an exception to commit/push this branch and create a draft PR; the failing gates remain disclosed and unresolved.
- Source base and final fetched origin/main: `8b1420ea1da7349db68b4a293bb37da049fb9047`.
- Selected tenant only: `festapp`, `prod/festapp`, `https://live.festapp.net`.
- Final fetched tenant branch tip: `0a8876868b8935d24231fafce599a22a8aadeb77`.
- Live manifest readback: version `0.20.161+645`, main asset `main.dart.0.20.161-645.js`. The live manifest does not expose source SHA; the branch tip is not represented as independent proof of deployed SHA.
- Live activation is `{schemaVersion:1, tenantId:festapp, generation:1, backend:canonical}`; tenant config has canonical phase, `https://api.festapp.net`, organization 1 and no forced occasion. No production event/user data was queried. Database identity/tenant-row verification is still required before release if its workflow reads such data.
- Final fetch and GitHub/live readback: `2026-10-17T22:13:58Z` (2026-10-18 in Europe/Prague). Source and tenant refs did not advance during this execution.
- Original dirty checkout was not changed. Only the two requested planning documents were copied into the isolated checkout as task context. No unrelated implementation diff was imported.

## Prepared implementation

- Occasion detail uses the existing escaping `html` and rich `sanitizeHtml` contracts. Title, date and button text cannot become markup. Button color accepts supported 3/6-digit hex and is assigned through DOM style properties with ThemeService contrast.
- Static SVG uses a separate DOMPurify instance per rendering window, sharing the existing instance-management pattern without changing rich HTML hooks. XML parse errors, non-SVG roots/namespaces and DTDs fail closed. CSS uses css-tree ASTs and a graphic-property allowlist. Scripts, foreignObject, navigation, events, SMIL, external CSS imports/URLs and nonlocal use references are excluded. Gradient/clip/local-use/text fixtures survive. HTTP(S) image URL backgrounds remain supported. Rejected backgrounds do not prevent seat rendering or callbacks.
- Canonical policy definitions live in `automation/lib/csp_policy.mjs`; `generate_csp_policy.mjs` computes exact SHA-256 inline hashes and whole-document digests from final artifacts. Both source `_headers` are generated from that owner/template. The build runs generation after HTML/version transforms. The verifier checks final documents and the manifest embedded in the Worker.
- Worker HTML branches select policies by actual document: webclient, Flutter, auth bridge, organizers, static documents and scriptless 404. This includes OAuth adapters, PWA cache entry aliases, form/home backend fallbacks and unknown Flutter links. Existing cache/redirect/referrer behavior is preserved.
- Candidate script policies have no unsafe-inline, unsafe-eval, wildcard or generic https: script allowance. Flutter alone has candidate wasm-unsafe-eval and the specific OneSignal CDN origin. Runtime acceptance of those candidates remains unproven until the release matrix passes. No unrelated image/connect/style/frame restriction was added.
- `/_security/csp-report` accepts bounded POST JSON: 32 KiB maximum stream, 10 reports maximum batch, validated MIME/shape and 204/no-store success. Logs contain only validated directive, disposition, fixed profile and bounded HTTP(S) origin (or fixed source category). Tokens, paths, query, fragment, credentials, referrer, sample and raw body are not logged. An isolate-local budget caps logs at 20 per minute; it is sampling, not a global edge rate limiter.
- `CSP_MODE` remains `report-only`. Enforcing response generation is implemented and tested, but promotion requires a reviewed mode change after the documented gate. The retry button's inline event attribute was replaced with addEventListener.
- Dependabot config covers exactly the five audited roots (web_client, image-worker, sync-worker, sync-publisher, self-hosted-monitor) plus GitHub Actions. Weekly schedule, two open PRs per entry, minor/patch grouping, no npm major version updates and no auto-merge. It is local and not yet active through main.

## Verification actually performed

| Check | Result |
| --- | --- |
| Requested HTML/detail/SVG/viewport/card Node batch | 21 passed |
| CSP policy + hosting + public SEO + Google auth hosting | 24 passed |
| Startup contract (`bash automation/test_web_startup.sh`) | 59 passed |
| `pnpm run build` in web_client | Passed; actual Vite production build, main development-template version 0.20.1+485, not a tenant release build |
| Isolated real Chromium security fixture | Passed without CSP and with enforcing fixture CSP: rich detail, gradients/clip/local use/text, zoom/pan, seat callback, reserve callback, Escape, malformed SVG rejection, no XSS execution, inline handler blocked |
| Browser synthetic report through actual Worker report handler on loopback | HTTP 204; sanitized local log contains only directive/disposition/profile/source. This is not a live report receipt |
| `pnpm run test:seat-checkout-browser` | Passed on both original disposable DB and fresh owned DB: actual map click -> SQL reservation -> preview -> order -> selected seat bound to ticket |
| First full `./automation/test_all.sh` | Web 416 passed / 9 skipped. SQL failed against preexisting stale disposable DB on 55432; no reset of that DB |
| Full suite with fresh owned main-baseline DB | Web 409 passed / 7 DB-dependent failures / 9 skipped; SQL 180 passed / 35 failed. SQL phase exits before later suites |
| Remaining Flutter/integration/automation lanes | Core 157 cases passed; adapters 78 cases passed (1 skipped); Flutter 1305 cases, 2 failed, architecture check failed for 3 unclassified roots; Deno 358 passed; image-worker integration 27 skipped because its required fixture credentials are absent |
| Existing apply-config/legal/deploy/migration wiring contracts | Passed |
| Updated update-prompt final-build fixture | Passed after adding final CSP generation/Worker stamp to the fixture; initial missing-manifest failure introduced by the new gate is fixed |
| Remaining canonical PWA/recovery automation batch | 134 passed / 2 failures in unchanged infrastructure contracts |
| Dependabot YAML parse and requested root count | Passed |
| `git diff --check` | Passed |

The new browser command is `pnpm run test:security-browser` in web_client. It uses a named local headless session with task-owned provider-free config and closes its server/session. The existing deterministic seat-checkout command was used unchanged. No production test content, order, notification or email was created.

## Concrete publication blockers

1. Fresh baseline/migrations still do not satisfy unchanged SQL tests. Examples independently reproduced: canonical source parity for `create_reception_user_v1(bigint,uuid,jsonb,bigint,text,boolean)` fails; `required_seat_checkout_test.sql` raises `abuse_limit_exceeded` for `email.ordinary.recipient.burst`. Other failures include `email_scope_mismatch`, retired writer contracts and canonical image URL requirements. Neither SQL functions nor abuse policy/host limits were changed by this task. The test runner's sequential retries also fail.
2. Seven web database-concurrency tests fail against the fresh main schema: waitlist accept/cancel/expiry, deletion/acceptance, tokenless admin withdrawal and Fakturoid swap recovery. Error examples include registration rejected with `abuse_limit_exceeded`. These use unchanged SQL-facing tests, separate from the passing security component tests.
3. Flutter has two unchanged sign-in-code failures: `code exchange receives mailbox, password fallback keeps tenant identity` and `accepted code refreshes returned session instead of password login`. Architecture also reports unclassified roots `test/components/images/recovering_image_test.dart`, `test/components/navigation/inventory_navigation_behavior_test.dart`, `test/components/eshop/report_number_format_test.dart`.
4. Remaining automation fails `assemble-abuse-migration.py --check` (canonical source/migration mismatch) and the online-restore contract assertion for `'runtime_executed':False`. These belong to unchanged backend/infrastructure paths outside this task.
5. GitHub main protection requires one approving PR review. Admin enforcement is off, but that is not authorization to bypass the review rule. The initial handoff did not publish because the full gate was failing. The user subsequently explicitly authorized a draft PR exception. That exception permits publication for review, while full gate repair and the required approving review remain prerequisites for merge/release.

Logs are local only: `/tmp/festapp-security-all-own-db.log`, `/tmp/festapp-security-db-isolated-failures.log`, `/tmp/festapp-security-remaining-gates.log`, `/tmp/festapp-security-automation-rest.log`, `/tmp/festapp-security-update-prompt.log`, `/tmp/festapp-security-browser-final.log`, `/tmp/festapp-security-seat-own-db.log`. Flutter lane JSON lives under `/var/folders/k4/bf8sn81n6395dn845t2gvjbm0000gn/T/festapp-client-4lvoskd0`. Logs are not committed or treated as passing evidence where a command failed.

## CSP rollout and compatibility gates still pending

Live GET/HEAD of `/` still has only `Content-Security-Policy: base-uri 'self'; object-src 'none'`; there is no newly deployed Report-Only policy or Reporting-Endpoints header. No live script enforcement is claimed.

A full release Flutter/CanvasKit build, actual login/logout/OAuth provider round trip, Flutter admin deep links, real push SDK initialization, existing-session PWA first/repeat/offline/online/update paths and representative embedded WebViews have not passed the required browser matrix. Startup/hosting unit tests are supporting evidence only. The enforcing component fixture is not a substitute for the whole release matrix. Static-host rewrite/profile behavior also needs a real host check if that adapter is ever released; this task authorizes Cloudflare for festapp only.

After repository prerequisites are repaired and the required PR review/merge is complete, delegate routine local build/deploy/live-version verification to gpt-6-luna low with the exact validated main/tenant SHAs, using automation/deploy_direct.sh for festapp only. Do not dispatch the GitHub Deploy workflow. First release the XSS repairs with Report-Only; verify real final-artifact hashes, coherent live version, all representative document headers and synthetic report receipt. Complete the matrix and resolve app-owned violations before promoting CSP_MODE to enforce. Rollback only the script enforcement to Report-Only while retaining XSS repairs and base/object restrictions.

## GitHub before/after

Repository: festappnet/festapp, public, organization plan Free, account has admin capability. Readbacks confirmed changes; no secrets were printed or pushed.

| Protection | Before | Readback after |
| --- | --- | --- |
| Secret scanning | disabled | enabled |
| Push protection | disabled | enabled |
| Vulnerability alerts | already enabled | GET HTTP 204 |
| Dependabot security updates | disabled | enabled, paused=false |
| Non-provider patterns | disabled | disabled |
| Validity checks | disabled | disabled |

PATCHes for the last two returned HTTP success but repeated GETs still show disabled, including separate structured-JSON requests and an explicit API version. They are **not enabled**. Organization is Free; [GitHub documents a Team/Secret Protection requirement for validity checks](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/customize-leak-detection/enable-validity-checks), and [non-provider API availability is described for Advanced Security customers](https://github.blog/changelog/2024-07-23-enable-secret-scanning-for-non-provider-patterns-on-repositories-with-the-rest-api/). No paid product was provisioned. The API did not return a specific 403 or an explanatory error; the observed blocker is lack of a confirmed available enablement path for this account/plan.

Open secret scanning alert readback returned an empty list; no scan-history completeness or secret validity assertion is inferred from that. No CI secret-scanner gate or broad allowlist was introduced.

## Cleanup and continuation

The owned SQL-only disposable project is `festapp-security-20261018`, loopback DB port 59112, workdir `/Users/miakh/source/festapp-security-db`; it was stopped after verification. Other database projects and the user's browser were left running unchanged. All owned test browser sessions and temporary Vite servers were closed by their harnesses.

This execution leaves a concrete, reviewable implementation in the isolated checkout. It does not mark the requested end-to-end hardening complete while repository publication, live reporting, compatibility and CSP enforcement remain blocked.

## Draft PR publication exception

The user explicitly accepted the requested exception for creating a draft PR despite the known failing full gate. Publication is limited to `security/web-hardening-20261018` against `main`, with the failures and pending CSP matrix disclosed. No merge, deployment, tenant branch change or protection bypass is included. Pre-publication fetch confirmed HEAD and origin/main both equal `8b1420ea1da7349db68b4a293bb37da049fb9047`; there is no upstream advancement to reconcile. The PR branch commit identifies the exact proposed source revision.

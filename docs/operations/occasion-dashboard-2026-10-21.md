# Unit occasion dashboard - 2026-10-21

## Behavior and read boundary

Inactive sale states (preparation, scheduled, paused, sold out, ended and finished)
use muted card content. Controls remain usable. Selling and waitlist states stay
active. Neutral corner icons retain tap/hover/focus tooltips, one-line labels and
the original card height. Scheduled countdowns use localized “Za {duration}”;
the tooltip identifies the sale start. Countdown-disabled forms keep date wording.

Initial unit navigation includes `unit_dashboard` inside `get_app_config_v219`.
Refresh uses one `get_unit_edit_data` RPC. Both call the same private, permission-
checked projection containing occasions, private drafts, app landing and demos.
The UI consumes that snapshot without independent catalogue/metadata reads;
concurrent screen refreshes share one pending future. Mutations remain separate.

The catalogue materializes actor-visible occasions before aggregating tickets
and users. Feature summaries expose code and enabled state, omitting editor-only
configuration. Editing and copying still load their authoritative detail data.

## Evidence

Read-only production comparison, org 3 largest managed unit (24 occasions):

| Catalogue | Previous | Updated |
| --- | ---: | ---: |
| JSON bytes | 145,102 | 31,160 |
| Warm SQL execution | 42.9-44.5 ms | 30.1-30.5 ms |

All fields were compared, excluding the intentional feature-summary projection.
Candidate SQL ran inline in a read-only transaction, without production DDL.
These are catalogue SQL measurements, not browser end-to-end load times. Existing
app-config logging is unchanged and was not benchmarked in a writable transaction.

Validation:
- 7 targeted SQL suites passed: dashboard authenticated/anonymous/outsider scope,
  payload, tenant context, sale states, copy configuration, landing, source parity.
- 60 Flutter cases passed for sale cards, demos, form ticket toggles and email previews.
- 6 unit-context cases passed, including an SDK transport assertion of exactly one
  refresh RPC and initial snapshot rendering without an initialized SDK.
- Targeted Dart analysis: no errors/warnings; 21 style/deprecation informational findings.
- Supplemental `security/rpc_object_authorization_test.sql` fails at its unrelated
  email-template fixture (“Own unit templates absent”). Reproduced with all changed
  existing SQL functions restored to pre-change HEAD inside a rolled-back local
  transaction. This is a baseline failure; the new dashboard authorization suite passes.

Release scope: vstupenky.online only; SQL migration 20261021230000, then web.
Stripe and Edge Function changes are outside this release.

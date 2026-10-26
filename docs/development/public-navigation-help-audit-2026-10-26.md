# Public navigation and help follow-up, 2026-10-26

The previous claim that all design commits were deployed did not prove that the
published guides had correct destinations. The contextual-help change
`5ec3a7a45` and web-authentication change `5436b9f80` were already in canonical
main by this audit. The remaining authored getting-started link still pointed
to the public `/events` catalogue. Organizer banking had no matching scope-aware
action. These were content/routing gaps in merged source, not missing branches.

Astra Medium reviewed navigation hierarchy and all authored Czech task guides.
Public organizer/help navigation now belongs to the shared header, outside the
account actions. Narrow layouts use a second row with 44px link targets. At
320px the guest settings control moves to that row to keep logo and sign-in
controls from overlapping. The catalogue body no longer duplicates these links.

The allowlisted `organization` and `bank-accounts` help actions select an
organizer independently of any occasion. Routing refreshes the selected unit
and requires its current administration/banking capability. No event draft is
created by opening an organization action. A changed signed-in actor invalidates
an open organizer chooser. Existing event actions retain the occasion chooser.

Czech and English guide sources now place organizer and bank actions beside
the relevant first step and explain the different scopes. The audit also fixes
duplicated payment wording, embed-navigation order, repeated navigation labels
and spacing between related-guide links. No banking, order, timezone or database
business behavior changes.

Verification: 32 targeted web/header/help cases, two complete help renderer and
content checks, five Flutter routing/picker cases, and targeted Dart analysis
with no errors or warnings (existing router/picker lint infos remain). A static
fixture uses the actual header component, CSS and fonts for signed-in/out
visual checks. At 320px there is no horizontal overflow, the guest logo clears
the first account action by 31px, and both navigation links have 44px targets.
Evidence: `/tmp/festapp-public-nav-20261026/` and matching
`/tmp/festapp-public-nav-*` logs. Production verification is recorded separately.

Live verification additionally found the organizer generator re-inserting the
old catalogue navigation after the static shell was cleaned. That producer is
removed as well, with a regression assertion against its generated catalogue.

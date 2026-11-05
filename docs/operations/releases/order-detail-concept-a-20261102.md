# Order detail Variant A release - 2026-11-02

Live: https://vstupenky.online, **0.20.485+991**.

- PR #699 merged with explicit user admin-merge approval; all five CI checks passed.
- Canonical main: `6fe018bacc3f7efc47fb7cd5d30a5f1d092e661c`.
- Published tenant: `prod/festapptickets`, `49f901023596e523e03a5bd16c4fd0edb1ebd61f`.
- Previous production `eb273a07a6d57f860a3e7dc7f9aa8d96047fcd62` preserved as ancestor.
- Canonical tenant overlay/drift, local Flutter and web-client build, and build verifier passed.
- Direct Pages deployment: https://1a56ee59.vstupenkyonline.pages.dev.
- Live version/build/legal checks passed three consecutive coherent probes; primary independently checked remote main/prod refs and deployment receipt.

Approved Variant A uses a compact header and financial summary, canonical editable contact/answer fields, form-defined phone visibility, standard directly editable hidden note and ticket/product contents without redundant navigation links. Native desktop and 400px/1.6 text-scale evidence is recorded under `docs/plans/evidence/order-detail-concept-a-20261102/`.

Escape release probes used real OrdersContent, router, dialog, focus and controllers with mocked transport: clean close removes detail route; dirty email stays protected behind the shared discard guard; modal Escape takes precedence; saving blocks close. Additional probes passed with focus in the grid, its filter input and outside the detail. Existing grid tests cover modal and active-cell edit precedence. Four initial targeted checks and five final full-route probes passed. Temporary probe source and logs are archived privately under `/Users/miakh/.local/share/festapp-design-previews/order-detail-20261102/native-a/`. No runtime change was needed after PR merge.

Logs: `/tmp/festapptickets-concept-a-build.log`, `/tmp/festapptickets-concept-a-deploy.log`, `/tmp/order-concept-a-escape.log`, `/tmp/order-concept-a-escape-outside.log`.
Release worktree: `/Users/miakh/source/festapp-festapptickets-order-concept-a-release-20261102`.

No backend/provider operations were performed. Local review ports 58631, 58621 and 58622 remain stopped, independently confirmed after deployment. Other projects and stored data were untouched.

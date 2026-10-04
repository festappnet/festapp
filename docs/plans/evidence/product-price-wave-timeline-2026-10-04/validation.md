# Price-wave timeline validation

The grid header action follows the ticket-scanning action pattern. The timeline
shows current product state first, then chronologically ordered shared terms.
Product controls stack at narrow widths and large text sizes. Scheduling dialogs
are scrollable and reuse CommonStrings.storno.

`automation/test_all.sh web flutter automation` passed. Targeted price scheduling
widget tests also passed. Timeline regression checks current state precedes future
prices and there are no horizontal scrollables at mobile width with larger text.
Targeted analyzer: no errors/warnings, three existing brace-style infos.
Configuration application, translation synchronization and diff hygiene passed.

Isolated headless visual fixture: 390x844 mobile timeline, 390x400 editor and
1280x900 desktop screenshots. Real widgets with synthetic data, no backend writes.
Database and RPC behavior are unchanged; no migration is required.

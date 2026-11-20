# Regional portal locale preference and startup recovery

Verification tier is standard. Start from PR #986 at `fe94465`. The public
checkout and Flutter web admin share an explicit locale choice through
`flutter.locale` and its explicit-selection marker on the same origin.

1. Let the checkout settings widget record a click on the already active
   language. The localization service persists the choice without reloading
   when that catalog is already rendered. Verify through the actual widget.
2. Make preference synchronization compare the last observed stored choice.
   A missing Slovak catalog may render Czech without repeatedly reloading
   on focus or page restoration. A newly stored choice remains actionable.
3. Feed the same preference resolver into the generated pre-module checkout
   shell, with the tenant languages and migration policy projected by
   `apply_config.sh`. Give Slovak startup and recovery messages their own
   language. Keep the shell usable with denied storage or missing modules.
4. Verify locale, startup and tenant config tests, plus the generated runtime
   check. Publish the fix on PR #986 after checking the current base and head.

Automatic legacy Czech and manually selected legacy Czech can be
indistinguishable because the old installation did not write the marker. The
existing tenant-scoped migration is retained. A deployment and its tenant
overlay remain separate from the PR update.

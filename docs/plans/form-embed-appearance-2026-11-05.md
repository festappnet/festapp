# Form-owned embed appearance

Superseded for the editor UI by the user correction on 2026-11-05: appearance is
selected beside copied embed code, with explicit inherit/default markup. The
saved field remains a compatibility fallback only; see embedded-checkout.md.

Implement one owner: `forms.data.design.embed_inherit_style` (boolean, default true).
The ordinary form save command, version checks and authoring permissions persist it.
Public FormModel and Dart FormDefinition use the same default. Standalone forms and
seat-map colors remain unchanged. Saving affects subsequent page loads; no forced
reload or database polling during checkout.

1. Extend the canonical metadata whitelist/boolean validation and add a forward
   migration. Cover save/read, invalid values, partial patches and reset.
2. Put the switch in form Design settings and remove it from the HTML generator.
3. Host embed.js always supplies bounded presentation tokens; EmbedBridge applies
   them only after loading the form setting. Keep parent/source/instance validation.
   Old data-festapp-style attributes are accepted as inert external markup.
4. Remove local appearance settings from WordPress (both products), Joomla (both
   products), Wix and help generator. Every supported renderer loads the shared
   helper in automatic and fixed height modes. Fixed height controls sizing only.
5. Update docs and tests; run targeted JS/Dart/disposable PostgreSQL checks and
   plugin contracts/build checks. No production release, CMS publication or live
   database migration is part of this implementation.

Compatibility: existing automatic embeds receive the updated unversioned helper
without replacing their HTML. Old installed plugin controls become inert with the
updated helper. Old fixed/no-helper embeds require a plugin update or adding the
helper once, because cross-origin pages cannot inspect their host without it.
A refreshed plugin removes the obsolete controls. Missing stored values mean true,
matching the default of the current generators. No per-embed overrides survive.

## Implemented and verified

SQL settings validation, Dart authoring snapshots and MCP forms.save share the
saved boolean. The Form Design switch uses the ordinary save and read-only state.
Embed dialog, help generator, WordPress, Joomla and Wix no longer own an override.
The shared helper always supplies presentation; the bridge waits for saved form
settings before applying it. Parent/source/instance checks and font cleanup remain.
WordPress regional/global outputs and Joomla regional/global modules regenerated.

Validation:

- Web client embed and help generator tests passed; generated WordPress editor
  JavaScript syntax checks passed.
- Wix widget/package tests and local build passed without publication.
- Core metadata tests passed (8 cases).
- Flutter tests selected by --name 'embed code|form appearance edits' passed
  (2 cases): code generation, saved draft change and read-only switch.
- PHP 8.4 isolated container: integrations/tests/embed-appearance-contract.php
  passed (16 actual WordPress/Joomla renderer cases, CMS APIs stubbed).
  WordPress metadata contract tests passed (4 cases).
- Guarded disposable PostgreSQL on loopback 55432: settings suite 14/15 passed,
  including save/read/replay, schema parity and boolean rejection/reset. Reminder
  inheritance fails creating its fixture order with code 1013. A transaction-local
  baseline removing the new key from SQL whitelist/validation reproduced the same
  failure. No unrelated order code or fixture was changed to hide this failure.
- Targeted diff whitespace check passed.

Unapplied: forward database migration, production Flutter/web release and CMS/Wix
publication. No installed CMS/live browser verification is claimed. Existing
helper-enabled embeds need a page refresh after release; historical no-helper
embeds need the one-time update described above.


## Architecture hardening review

The second pass reproduced and corrected three regressions before accepting the
architecture:

1. An invalid host theme could replace the bridge cache even though the renderer
   rejected it; disabling/re-enabling then lost the last valid theme. `EmbedTheme`
   now owns the saved enable state and normalized presentation, including bounded
   font definitions. Bridge only authenticates messages and coordinates rendering.
2. A released full-metadata client could erase a setting it did not know. The
   existing released-client transport boundary preserves an omitted preference;
   explicit booleans/null still go through the same canonical settings validator.
   The unapplied forward migration now includes the canonical command owner.
3. A projected checkout price button could be selected as the website's primary
   button, feeding generated appearance back into its own input (including other
   embeds). Host style discovery now excludes all price projections.

FormPage applies the embed preference at its common applyTheme boundary for every
form presentation route. Removed the constant Joomla helper flag/branch and the
unreachable Wix checkbox handling. Corrected the remaining setup/guide references.

Verification after hardening:

- 22 embed regressions plus a real FormPage/Bridge/EmbedTheme integration case
  passed. The latter covers host-first and form-first loading, disabled form
  settings, navigation, stale responses and cleanup; unrelated transport/content
  and base service-theme work is simulated.
- 16 actual WordPress/Joomla PHP renderer cases passed (CMS APIs stubbed).
- Wix widget/package tests and build passed after removing obsolete handling.
- Full settings PostgreSQL suite: 15/16 passed, including old-client omission,
  explicit reset, malformed design rejection, atomicity and schema parity. The
  previously confirmed baseline reminder fixture failure (code 1013) remains.
- The new migration matches its canonical SQL function/command owners; targeted
  diff whitespace checks passed. No production deployment or migration performed.


## Reminder test failure resolved

The remaining failure was diagnosed rather than waived. Its actual order error
was `function public.notification_center_prepared_invalidate_order(bigint) does
not exist`. The shared form fixture installed current notification producers but
omitted their canonical prepared-projection schema/functions. Added the real
canonical dependencies to that fixture. The SQL consumer wrapper now honors the
same `-- test-setup:` declarations as the repository SQL runner, including the
reminder workload fixture previously omitted by its hardcoded setup list. The
order assertion now includes the actual response so future failures retain their
cause. No production behavior, test assertion or test selection was weakened.

Final command against the marker-guarded disposable loopback PostgreSQL:
`pnpm --dir tools/festapp exec node --test --test-reporter=spec
 test/forms-settings-postgres.test.mjs` (with explicit local database environment).
Result: **16 passed, 0 failed, 0 skipped**. All earlier 14/15 and 15/16 counts
above are historical; this result supersedes their unresolved status.

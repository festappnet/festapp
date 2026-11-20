# Shared browser preferences

Flutter and the public web client share settings within the same browser origin.
Native applications retain their device-local preferences; these settings are
not account data and do not synchronize across devices or tenant domains.

- `theme`: plain `light`, `dark`, or `auto`. `SyncedAdaptiveTheme` and
  `ThemeService` publish and receive this value. The former AdaptiveTheme keys
  are read only to migrate a browser without a shared choice.
- `flutter.locale`: a JSON-encoded language string, for example `"en"`, matching
  EasyLocalization's existing SharedPreferences format. Flutter publishes through
  EasyLocalization; `LocalizationService` writes the same encoding. The former
  public `locale` key is read only for migration. `prepareSharedLocale` performs
  that migration before EasyLocalization initializes its cached locale.
- `flutter.locale.manuallySelected`: the value `true` records a choice made
  through either language selector, including a click on the active language.
  The regional migration treats cached Czech without this marker as automatic.
  Older manually selected Czech can be indistinguishable from an automatic
  value. Choosing Czech again records the explicit preference.

Without an explicit choice, the first supported browser language wins, then
the tenant default. The public startup shell and the public app use the same
locale resolver. If the selected translation catalog is unavailable, the
public app can render the default catalog while preserving the stored choice.

Both applications reconcile shared changes on storage events, focus and page
restoration. An open public page compares the latest stored choice with its
last observed choice so catalog fallback does not cause repeated reloads.
Explicitly localized marketing URLs keep their document language and never
replace the application preference.

Regression targets: `test/widgets/synced_adaptive_theme_test.dart`,
`test/startup/startup_language_test.dart`, the two preference suites in
`test/browser/`, and `web_client/tests/core/{theme,locale}_preference.test.js`.

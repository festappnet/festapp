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

Both applications receive changes through storage events and reconcile on focus
or page restoration. Flutter updates its localization provider; public app pages
reload when their selected language changes, as with their language selector.
Explicitly localized marketing URLs keep their document language and never
replace the application preference.

Regression targets: `test/widgets/synced_adaptive_theme_test.dart`,
`test/startup/startup_language_test.dart`, the two preference suites in
`test/browser/`, and `web_client/tests/core/{theme,locale}_preference.test.js`.

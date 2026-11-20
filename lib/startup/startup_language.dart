import 'dart:ui';

import 'package:fstapp/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/locale_preference/locale_preference_store.dart';
import '../services/locale_preference/locale_preference_stub.dart'
    if (dart.library.js_interop) '../services/locale_preference/locale_preference_web.dart';

const startupLanguages = {'cs', 'en', 'sk', 'de', 'pl', 'uk', 'es'};

/// Match the first supported browser language, falling back to the tenant default.
Locale resolveBrowserLocale(
  Iterable<Locale> preferences, {
  Iterable<Locale>? supportedLocales,
}) {
  final supported = {
    for (final locale
        in supportedLocales ??
            AppConfig.availableLanguages().map((e) => e.locale))
      locale.languageCode: locale,
  };
  for (final locale in preferences) {
    final match = supported[locale.languageCode];
    if (match != null) return match;
  }
  return supported.values.first;
}

/// Migrate the former public-client choice before EasyLocalization caches it.
Future<void> prepareSharedLocale() async {
  final store = createLocalePreferenceStore();
  if (!store.enabled) return;
  final language = store.read();
  final preferences = await SharedPreferences.getInstance();
  final previous = preferences.getString('locale');
  if (previous == language) return;
  if (language == null) {
    await preferences.remove('locale');
  } else {
    await preferences.setString('locale', language);
  }
}

/// Record a human selection even when it matches the currently detected language.
Future<void> rememberSharedLocaleChoice(Locale locale) async {
  if (!createLocalePreferenceStore().enabled) return;
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(explicitLocalePreference, true);
  await preferences.setString('locale', locale.languageCode);
}

/// Reads EasyLocalization's preference without translation assets or IndexedDB.
/// A blocked preferences plugin must not hold up the startup failure surface.
Future<String> resolveStartupLanguage({
  Future<String?> Function()? readSavedLanguage,
  String? defaultLanguage,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final configured =
      defaultLanguage ??
      AppConfig.availableLanguages().first.locale.languageCode;
  final fallback = startupLanguages.contains(configured) ? configured : 'en';
  final store = createLocalePreferenceStore();
  if (readSavedLanguage == null && defaultLanguage == null && store.enabled) {
    return store.read() ??
        resolveBrowserLocale(PlatformDispatcher.instance.locales).languageCode;
  }
  try {
    final saved =
        await (readSavedLanguage ??
                () async {
                  final shared = createLocalePreferenceStore().read();
                  if (shared != null) return shared;
                  final preferences = await SharedPreferences.getInstance();
                  return preferences.getString('locale');
                })()
            .timeout(timeout);
    final language = saved?.toLowerCase().split(RegExp('[_-]')).first;
    return startupLanguages.contains(language) ? language! : fallback;
  } catch (_) {
    return fallback;
  }
}

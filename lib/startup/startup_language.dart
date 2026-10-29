import 'package:fstapp/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/locale_preference/locale_preference_stub.dart'
    if (dart.library.js_interop) '../services/locale_preference/locale_preference_web.dart';

const startupLanguages = {'cs', 'en', 'sk', 'de', 'pl', 'uk'};

/// Migrate the former public-client choice before EasyLocalization caches it.
Future<void> prepareSharedLocale() async {
  final store = createLocalePreferenceStore();
  if (!store.enabled) return;
  final language = store.read()?.toLowerCase().split(RegExp('[_-]')).first;
  if (!AppConfig.availableLanguages().any(
    (item) => item.locale.languageCode == language,
  )) {
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getString('locale') != language) {
    await preferences.setString('locale', language!);
  }
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

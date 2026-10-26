import 'package:fstapp/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const startupLanguages = {'cs', 'en', 'sk', 'de', 'pl', 'uk'};

/// Reads EasyLocalization's preference without translation assets or IndexedDB.
/// A blocked preferences plugin must not hold up the startup failure surface.
Future<String> resolveStartupLanguage({
  Future<String?> Function()? readSavedLanguage,
  String? defaultLanguage,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final configured = defaultLanguage ??
      AppConfig.availableLanguages().first.locale.languageCode;
  final fallback = startupLanguages.contains(configured) ? configured : 'en';
  try {
    final saved = await (readSavedLanguage ??
            () async {
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

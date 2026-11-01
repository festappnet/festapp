@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'theme_preference_store_browser_cases.dart' as theme;
import 'locale_preference_store_browser_cases.dart' as locale;

void main() {
  group('browser_theme_preferences', theme.main);
  group('browser_locale_preferences', locale.main);
}

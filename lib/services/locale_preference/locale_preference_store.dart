import 'package:flutter/foundation.dart';

const explicitLocalePreference = 'locale.manuallySelected';

/// The browser locale shared with EasyLocalization and the public client.
abstract interface class LocalePreferenceStore {
  bool get enabled;
  String? read();
  VoidCallback listen(VoidCallback onChanged);
}

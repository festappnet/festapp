import 'package:flutter/foundation.dart';

import 'theme_preference_store.dart';

ThemePreferenceStore createThemePreferenceStore() => const _NativeStore();

class _NativeStore implements ThemePreferenceStore {
  const _NativeStore();
  @override
  bool get enabled => false;
  @override
  String? read() => null;
  @override
  String? readLegacy() => null;
  @override
  void write(String mode) {}
  @override
  VoidCallback listen(VoidCallback onChanged) => () {};
}

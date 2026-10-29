import 'package:flutter/foundation.dart';

import 'locale_preference_store.dart';

LocalePreferenceStore createLocalePreferenceStore() => const _NativeStore();

class _NativeStore implements LocalePreferenceStore {
  const _NativeStore();
  @override
  bool get enabled => false;
  @override
  String? read() => null;
  @override
  VoidCallback listen(VoidCallback onChanged) => () {};
}

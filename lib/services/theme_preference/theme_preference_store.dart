import 'package:flutter/foundation.dart';

/// Browser preference shared by the public client and Flutter administration.
/// Native apps retain AdaptiveTheme's own persistence.
abstract interface class ThemePreferenceStore {
  bool get enabled;
  String? read();
  String? readLegacy();
  void write(String mode);
  VoidCallback listen(VoidCallback onChanged);
}

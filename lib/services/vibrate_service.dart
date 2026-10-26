import 'package:flutter/services.dart';

class VibrateService {
  /// Provides haptic feedback for a successful action.
  static void vibrateOk() {
    HapticFeedback.lightImpact();
  }

  /// Provides haptic feedback for a non-successful action.
  static void vibrateNotOk() {
    HapticFeedback.lightImpact();
    HapticFeedback.lightImpact();
  }
}

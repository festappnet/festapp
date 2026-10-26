import 'package:flutter/foundation.dart';

class AppLogger {
  static void debug(String message) => debugPrint(message);
  static void warning(String message) => debugPrint('[WARN] $message');
  static void error(String message) => debugPrint('[ERROR] $message');
}

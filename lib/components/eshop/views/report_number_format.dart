import 'package:festapp_core/formatting.dart';

/// Format server decimals using the shared display policy without precision loss.
String formatReportNumber(String value, {String? locale}) =>
    formatExactDisplayNumber(value, locale: locale);

import 'package:intl/intl.dart';

/// Format the server's exact decimal strings without losing monetary precision.
String formatReportNumber(String value, {String? locale}) {
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) return value;
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final parts = value.split('.');
  final integer = parts.first.replaceAllMapped(
      RegExp(r'\d(?=(\d{3})+$)'), (match) => '${match[0]}${symbols.GROUP_SEP}');
  return parts.length == 1
      ? integer
      : '$integer${symbols.DECIMAL_SEP}${parts[1]}';
}

import 'package:intl/intl.dart';

/// Presentation only: group digits from absolute 10000, preserving locale rules.
const numberGroupingThreshold = 10000;

String _format(NumberFormat formatter, num value) {
  if (value.abs() < numberGroupingThreshold) formatter.turnOffGrouping();
  return formatter.format(value);
}

String formatDisplayNumber(num value, {String? locale, int? decimalDigits}) {
  final formatter = NumberFormat.decimalPattern(locale);
  if (decimalDigits != null) {
    formatter.minimumFractionDigits = decimalDigits;
    formatter.maximumFractionDigits = decimalDigits;
  }
  return _format(formatter, value);
}

/// Preserves a grid's precision and explicit identifier formats.
String formatDisplayPattern(num value, String pattern, {String? locale}) =>
    _format(NumberFormat(pattern, locale), value);

String formatDisplayCurrency(
  num value, {
  String? locale,
  String? name,
  String? symbol,
  int? decimalDigits,
  bool simple = false,
}) {
  return _format(
    simple
        ? NumberFormat.simpleCurrency(
            locale: locale,
            name: name,
            decimalDigits: decimalDigits,
          )
        : NumberFormat.currency(
            locale: locale,
            name: name,
            symbol: symbol,
            decimalDigits: decimalDigits,
          ),
    value,
  );
}

/// Retains exact server decimal strings, including values beyond double precision.
String formatExactDisplayNumber(String value, {String? locale}) {
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) return value;
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final parts = value.split('.');
  final digits = parts.first
      .replaceFirst('-', '')
      .replaceFirst(RegExp(r'^0+'), '');
  final integer = digits.length < numberGroupingThreshold.toString().length
      ? parts.first
      : parts.first.replaceAllMapped(
          RegExp(r'\d(?=(\d{3})+$)'),
          (match) => '${match[0]}${symbols.GROUP_SEP}',
        );
  return parts.length == 1
      ? integer
      : '$integer${symbols.DECIMAL_SEP}${parts[1]}';
}

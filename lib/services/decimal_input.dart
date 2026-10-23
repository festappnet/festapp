/// Decimal user input accepts either a comma or a dot, without grouping.
/// Validation and persistence must use this same parser.
class DecimalInput {
  static double? tryParse(String? input) {
    final normalized = input?.trim().replaceAll(',', '.');
    if (normalized == null ||
        !RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(normalized)) {
      return null;
    }
    final value = double.tryParse(normalized);
    return value != null && value.isFinite ? value : null;
  }

  static int? positiveDurationSeconds(String? input,
      {required int secondsPerUnit}) {
    final value = tryParse(input);
    if (value == null || value <= 0) return null;
    final seconds = value * secondsPerUnit;
    // Durations are persisted in a PostgreSQL integer column.
    if (!seconds.isFinite || seconds > 2147483647) return null;
    final rounded = seconds.round();
    return rounded > 0 ? rounded : null;
  }
}

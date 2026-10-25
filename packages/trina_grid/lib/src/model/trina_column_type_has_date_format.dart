import 'package:intl/intl.dart' as intl;

abstract class TrinaColumnTypeHasDateFormat {
  const TrinaColumnTypeHasDateFormat({
    required this.dateFormat,
    required this.headerFormat,
    required this.headerDateFormat,
  });

  final intl.DateFormat dateFormat;

  final String headerFormat;

  final intl.DateFormat headerDateFormat;
}

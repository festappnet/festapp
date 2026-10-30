import 'package:festapp_core/formatting.dart';
import 'package:trina_grid/trina_grid.dart';

/// Display only: retain numeric sorting, editing and custom column formatters.
TrinaColumn withDisplayNumberFormatting(
  TrinaColumn column,
  String Function() locale,
) {
  final type = column.type;
  if (column.formatter != null || type is! TrinaColumnTypeNumber) return column;
  column.formatter = (value) {
    if (value == null) return '';
    final number = value is num
        ? value
        : num.tryParse(
            value.toString().replaceAll(
              type.numberFormat.symbols.DECIMAL_SEP,
              '.',
            ),
          );
    if (number == null) return type.applyFormat(value);
    return formatDisplayPattern(
      !type.negative && number < 0 ? 0 : number,
      type.format,
      locale: type.locale ?? locale(),
    );
  };
  return column;
}

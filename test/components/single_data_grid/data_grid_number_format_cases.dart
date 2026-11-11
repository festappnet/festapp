import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/single_data_grid/data_grid_number_format.dart';
import 'package:trina_grid/trina_grid.dart';

void main() {
  test(
    'grid applies grouping threshold without changing editing or sorting',
    () {
      final column = withDisplayNumberFormatting(
        TrinaColumn(
          title: 'Amount',
          field: 'amount',
          type: TrinaColumnType.number(format: '#,##0.00'),
        ),
        () => 'cs',
      );
      expect(column.formattedValueForDisplay(1350.5), '1350,50');
      expect(column.formattedValueForDisplay(10000), '10\u00a0000,00');
      expect(column.formattedValueForDisplay(-1350.5), '-1350,50');
      expect(column.formattedValueForDisplay(null), '');
      expect(column.formattedValueForDisplayInEditing(1350.5), '1350.5');
      expect(column.type.compare(9999, 10000), lessThan(0));
    },
  );
  test('explicit identifiers and custom formatters retain their contracts', () {
    final id = withDisplayNumberFormatting(
      TrinaColumn(
        title: 'ID',
        field: 'id',
        type: TrinaColumnType.number(format: '#'),
      ),
      () => 'cs',
    );
    expect(id.formattedValueForDisplay(12345), '12345');
    final custom = withDisplayNumberFormatting(
      TrinaColumn(
        title: 'Custom',
        field: 'custom',
        type: TrinaColumnType.number(),
        formatter: (value) => 'custom $value',
      ),
      () => 'cs',
    );
    expect(custom.formattedValueForDisplay(1350), 'custom 1350');
  });
}

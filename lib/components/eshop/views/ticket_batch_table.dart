import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_header.dart';
import 'package:fstapp/theme_config.dart';
import 'package:trina_grid/trina_grid.dart';
import '../ticket_batch_strings.dart';
import '../orders_strings.dart';

/// Uses the same compact, sortable grid and theme as the adjacent order lists.
class TicketBatchTable extends StatelessWidget {
  const TicketBatchTable({super.key, required this.rows, required this.onOpen});
  final List<Map> rows;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    TrinaColumn column(String field, String label,
            {bool numeric = false, double width = 120}) =>
        TrinaColumn(
            title: label,
            field: field,
            width: width,
            type: numeric
                ? TrinaColumnType.number(
                    format: field == 'stockValue' || field == 'receivedAmount'
                        ? '#,##0.00'
                        : '#,##0',
                    locale: Localizations.localeOf(context).languageCode)
                : TrinaColumnType.text(),
            enableEditingMode: false,
            textAlign: numeric
                ? TrinaColumnTextAlign.right
                : TrinaColumnTextAlign.left,
            renderer: field == 'title'
                ? (cell) => Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                        onPressed: () =>
                            onOpen(cell.row.cells['id']!.value as String),
                        child: Text(cell.cell.value.toString(),
                            maxLines: 1, overflow: TextOverflow.ellipsis)))
                : null);
    return Container(
        padding: const EdgeInsets.all(3),
        color: ThemeConfig.whiteColor(context),
        child: TrinaGrid(
            key: ObjectKey(rows),
            configuration: SingleDataGridHeader.defaultTrinaGridConfiguration(
                context, Localizations.localeOf(context).languageCode),
            mode: TrinaGridMode.readOnly,
            columns: [
              column('title', TicketBatchStrings.text('name'), width: 280),
              column('available', TicketBatchStrings.available, numeric: true),
              column('sold', TicketBatchStrings.sold, numeric: true),
              column('voided', TicketBatchStrings.voided, numeric: true),
              column('stockValue', TicketBatchStrings.text('stockValue'),
                  numeric: true, width: 230),
              column(
                  'receivedAmount', TicketBatchStrings.text('receivedAmount'),
                  numeric: true, width: 180),
              column('currency', OrdersStrings.gridCurrency, width: 90),
            ],
            rows: rows.map((batch) {
              final counts = batch['counts'] as Map;
              return TrinaRow(cells: {
                for (final entry in <String, dynamic>{
                  'id': batch['id'],
                  'title': batch['title'],
                  'available': counts['available'],
                  'sold': counts['soldActive'],
                  'voided': (counts['voidedUnsold'] as num? ?? 0) +
                      (counts['cancelledAfterSale'] as num? ?? 0),
                  'stockValue': batch['stockValue'] ?? 0,
                  'receivedAmount': batch['receivedAmount'] ?? 0,
                  'currency': batch['currency'],
                }.entries)
                  entry.key: TrinaCell(value: entry.value),
              });
            }).toList()));
  }
}

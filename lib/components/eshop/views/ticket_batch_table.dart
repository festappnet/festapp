import 'package:material_ui/material_ui.dart';
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
            cellPadding: EdgeInsets.zero,
            renderer: (cell) => Semantics(
                button: true,
                child: InkWell(
                    onTap: () => onOpen(cell.row.cells['id']!.value as String),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                            alignment: numeric
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Text(
                                cell.column.formattedValueForDisplay(cell.cell.value),
                                style: cell.stateManager.style.cellTextStyle.copyWith(
                                    color: field == 'title'
                                        ? Theme.of(context).colorScheme.primary
                                        : null),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis))))));
    return Container(
        padding: const EdgeInsets.all(3),
        color: ThemeConfig.whiteColor(context),
        child: TrinaGrid(
            key: ObjectKey(rows),
            configuration: SingleDataGridHeader.defaultTrinaGridConfiguration(
                context, Localizations.localeOf(context).languageCode),
            mode: TrinaGridMode.selectWithOneTap,
            onSelected: (event) {
              final id = event.row?.cells['id']?.value;
              if (id is String) onOpen(id);
            },
            columns: [
              TrinaColumn(
                  title: TicketBatchStrings.text('detailAndPrint'),
                  field: 'actions',
                  width: 180,
                  frozen: TrinaColumnFrozen.start,
                  type: TrinaColumnType.text(),
                  enableEditingMode: false,
                  enableSorting: false,
                  enableFilterMenuItem: false,
                  enableContextMenu: false,
                  renderer: (cell) => Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: () =>
                              onOpen(cell.row.cells['id']!.value as String),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(
                              TicketBatchStrings.text('detailAndPrint'))))),
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
                  'actions': '',
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

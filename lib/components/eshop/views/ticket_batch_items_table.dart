import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_header.dart';
import 'package:fstapp/theme_config.dart';
import 'package:trina_grid/trina_grid.dart';
import '../eshop_column_ids.dart';
import '../eshop_columns.dart';
import '../order_item_strings.dart';
import '../orders_strings.dart';
import '../ticket_batch_strings.dart';

/// Selection stays owned by the batch page, including tickets selected by QR.
class TicketBatchItemsTable extends StatefulWidget {
  const TicketBatchItemsTable({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelectionChanged,
    this.enabled = true,
  });

  final List<dynamic> items;
  final Set<int> selected;
  final ValueChanged<Set<int>> onSelectionChanged;
  final bool enabled;

  @override
  State<TicketBatchItemsTable> createState() => _TicketBatchItemsTableState();
}

class _TicketBatchItemsTableState extends State<TicketBatchItemsTable> {
  TrinaGridStateManager? _manager;

  bool _available(TrinaRow row) => row.cells['available']!.value == true;

  @override
  void didUpdateWidget(covariant TicketBatchItemsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _manager = null;
    } else {
      // Keep sorting/filtering while QR lookup or a sale updates the selection.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final manager = _manager;
        if (manager == null) return;
        for (final row in manager.refRows.originalList) {
          row.setChecked(widget.selected.contains(row.cells['id']!.value));
        }
        manager.notifyListeners();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    TrinaColumn column(String field, String title,
            {double width = 180, bool numeric = false}) =>
        TrinaColumn(
            title: title,
            field: field,
            width: width,
            type: numeric
                ? TrinaColumnType.number(format: '#,##0')
                : TrinaColumnType.text(),
            enableEditingMode: false);
    final ordinal = column('ordinal', '#', width: 110, numeric: true)
      ..frozen = TrinaColumnFrozen.start
      ..enableRowChecked = true
      ..disableRowCheckboxWhen = (row) => !widget.enabled || !_available(row);
    return Container(
        padding: const EdgeInsets.all(3),
        color: ThemeConfig.whiteColor(context),
        child: TrinaGrid(
            key: ObjectKey(widget.items),
            mode: TrinaGridMode.readOnly,
            configuration: SingleDataGridHeader.defaultTrinaGridConfiguration(
                context, Localizations.localeOf(context).languageCode),
            onLoaded: (event) {
              _manager = event.stateManager;
              event.stateManager.setShowColumnFilter(true);
            },
            onRowChecked: (event) {
              if (!widget.enabled) return;
              final manager = _manager;
              if (manager == null) return;
              final selected = <int>{};
              for (final row in manager.refRows.originalList) {
                if (!_available(row)) {
                  row.setChecked(false);
                } else if (row.checked == true) {
                  selected.add(row.cells['id']!.value as int);
                }
              }
              widget.onSelectionChanged(selected);
            },
            columns: [
              ordinal,
              ...EshopColumns.generateColumns(
                  context, [EshopColumnIds.TICKET_DOWNLOAD]),
              column('symbol', OrderItemStrings.itemSymbol, width: 220),
              column('state', OrdersStrings.gridState),
              column('order', OrdersStrings.gridOrder, numeric: true),
            ],
            rows: widget.items.map((item) {
              final available =
                  item['sale_order_id'] == null && item['state'] == 'ordered';
              return TrinaRow(
                  checked: widget.selected.contains(item['id']),
                  cells: {
                    'id': TrinaCell(value: item['id']),
                    EshopColumnIds.TICKET_ID: TrinaCell(value: item['id']),
                    EshopColumnIds.TICKET_SYMBOL:
                        TrinaCell(value: item['ticket_symbol']),
                    EshopColumnIds.TICKET_STATE:
                        TrinaCell(value: item['state']),
                    EshopColumnIds.TICKET_DOWNLOAD: TrinaCell(value: ''),
                    'available': TrinaCell(value: available),
                    'ordinal': TrinaCell(value: item['ordinal']),
                    'symbol': TrinaCell(value: item['ticket_symbol']),
                    'state': TrinaCell(
                        value: item['state'] == 'storno'
                            ? TicketBatchStrings.voided
                            : available
                                ? TicketBatchStrings.available
                                : TicketBatchStrings.sold),
                    'order': TrinaCell(value: item['sale_order_id']),
                  });
            }).toList()));
  }
}

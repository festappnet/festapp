import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:intl/intl.dart';
import '../models/orders_history_model.dart';
import '../orders_strings.dart';
import 'order_state_display.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class OrderHistoryDialog extends StatefulWidget {
  final int orderId;
  const OrderHistoryDialog({super.key, required this.orderId});

  @override
  State<OrderHistoryDialog> createState() => _OrderHistoryDialogState();
}

class _OrderHistoryDialogState extends State<OrderHistoryDialog> {
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = true;
  List<OrderHistoryModel> _processedHistory = [];
  String _customerName = "";
  String _orderSymbol = "";

  double? _optimalTagWidth;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_optimalTagWidth == null) {
      // Get all possible state labels to find the longest one, which ensures
      // all tags have a consistent and sufficient width.
      final allStateLabels = OrderModel.orderStates
          .map((key) => OrderModel.statesDataGridToUpper(
              OrderModel.statesDataGridToUpper(key)))
          .toList();

      _optimalTagWidth = OrderStateDisplay.calculateOptimalWidth(
        context: context,
        stateLabels: allStateLabels,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    try {
      final bundle = await DbOrders.getOrderHistory(widget.orderId);
      final order = bundle.order;
      final history = bundle.history;

      final allHistoryItems = <OrderHistoryModel>[];
      allHistoryItems.addAll(history);

      for (var h in allHistoryItems) {
        h.orderModel = order;
      }

      if (history.isNotEmpty) {
        final latestHistoryRecord = history.last;
        if (order.updatedAt != null &&
            order.updatedAt!
                    .difference(latestHistoryRecord.createdAt!)
                    .inSeconds >
                5) {
          if (order.state != latestHistoryRecord.state ||
              order.price != latestHistoryRecord.price) {
            allHistoryItems.add(OrderHistoryModel.fromOrderModel(order));
          }
        }
      } else {
        allHistoryItems.add(OrderHistoryModel.fromOrderModel(order));
      }

      for (int i = 1; i < allHistoryItems.length; i++) {
        allHistoryItems[i].previousHistoryRecord = allHistoryItems[i - 1];
      }

      allHistoryItems.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

      if (mounted) {
        setState(() {
          _processedHistory = allHistoryItems;
          _customerName = order.toCustomerData();
          _orderSymbol = order.orderSymbol ?? "";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: SelectableText(
          "${OrdersStrings.gridHistory} $_orderSymbol - $_customerName"),
      content: SizedBox(
        width: 600,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _processedHistory.isEmpty
                ? Center(child: SelectableText(OrdersStrings.noHistoryFound))
                : SelectableRegion(
                    focusNode: _focusNode,
                    selectionControls: MaterialTextSelectionControls(),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _processedHistory.length,
                      itemBuilder: (context, index) {
                        final item = _processedHistory[index];
                        return _buildHistoryEntry(item);
                      },
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.close),
        ),
      ],
    );
  }

  Widget _buildHistoryEntry(OrderHistoryModel item) {
    final theme = Theme.of(context);
    final date = item.createdAt != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(item.createdAt!.toOccasionTime())
        : OrdersStrings.currentState;

    final changedBy =
        item.createdBy?.toFullNameString() ?? OrdersStrings.systemUser;
    final trinaRow = item.toTrinaRow(context);
    final stateCellFormat = trinaRow.cells[EshopColumns.HISTORY_STATE]!.value;

    final previousRecord = item.previousHistoryRecord;
    final priceHasChanged =
        previousRecord != null && item.price != previousRecord.price;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date, style: theme.textTheme.titleMedium),
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14, color: theme.textTheme.bodySmall?.color),
                    const SizedBox(width: 4),
                    Text(changedBy, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(
                OrdersStrings.gridState,
                Align(
                  alignment: Alignment.centerLeft,
                  child: OrderStateDisplay(
                    formattedState: stateCellFormat,
                    getBackground: OrderModel.singleDataGridStateToColor,
                    stateTagWidth: _optimalTagWidth,
                    enableWrapping: true,
                  ),
                )),
            const SizedBox(height: 12),
            _buildInfoRow(
              OrdersStrings.changes,
              item.generateMultiLineSummaryWidget(context),
              alignTop: true,
            ),
            if (item.price != null) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("${OrdersStrings.totalPrice}: ",
                      style: theme.textTheme.labelLarge),
                  if (priceHasChanged)
                    Row(
                      children: [
                        Text(
                          Utilities.formatPrice(context, previousRecord.price!,
                              currencyCode: previousRecord.currencyCode),
                          style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: theme.textTheme.bodySmall?.color),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(Icons.arrow_forward, size: 16),
                        ),
                        Text(
                          Utilities.formatPrice(context, item.price!,
                              currencyCode: item.currencyCode),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  else
                    Text(
                      Utilities.formatPrice(context, item.price!,
                          currencyCode: item.currencyCode),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, Widget valueWidget,
      {bool alignTop = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment:
            alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 16),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

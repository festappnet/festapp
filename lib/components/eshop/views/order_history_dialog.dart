import 'package:fstapp/widgets/app_dialog.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:intl/intl.dart';

import '../models/orders_history_model.dart';
import '../orders_strings.dart';
import 'order_state_display.dart';

class OrderHistoryContent extends StatefulWidget {
  final int orderId;
  const OrderHistoryContent({super.key, required this.orderId});

  @override
  State<OrderHistoryContent> createState() => _OrderHistoryContentState();
}

class _OrderHistoryContentState extends State<OrderHistoryContent> {
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = true;
  List<OrderHistoryModel> _processedHistory = [];

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
          .map(
            (key) => OrderModel.statesDataGridToUpper(
              OrderModel.statesDataGridToUpper(key),
            ),
          )
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
    return SizedBox(
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
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _processedHistory.length,
                itemBuilder: (context, index) {
                  final item = _processedHistory[index];
                  return _buildHistoryEntry(item);
                },
              ),
            ),
    );
  }

  Widget _buildHistoryEntry(OrderHistoryModel item) {
    final theme = Theme.of(context);
    final date = item.createdAt != null
        ? DateFormat.yMd().add_jms().format(item.createdAt!.toOccasionTime())
        : OrdersStrings.currentState;

    final changedBy =
        item.createdBy?.toFullNameString() ?? OrdersStrings.systemUser;
    final trinaRow = item.toTrinaRow(context);
    final stateCellFormat = trinaRow.cells[EshopColumnIds.HISTORY_STATE]!.value;

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
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(date, style: theme.textTheme.titleMedium),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: theme.textTheme.bodySmall?.color,
                    ),
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
                  getBackground: OrderStateDisplay.historyBackground,
                  stateTagWidth: _optimalTagWidth,
                  enableWrapping: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              OrdersStrings.changes,
              item.generateMultiLineSummaryWidget(context),
              alignTop: true,
            ),
            if (previousRecord != null &&
                previousRecord.data?['email'] != item.data?['email'])
              _buildInfoRow(
                OrdersStrings.gridEmail,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      previousRecord.data?['email']?.toString() ?? '',
                    ),
                    const Icon(Icons.arrow_downward, size: 16),
                    SelectableText(item.data?['email']?.toString() ?? ''),
                  ],
                ),
                alignTop: true,
              ),
            if (item.price != null) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "${OrdersStrings.totalPrice}: ",
                    style: theme.textTheme.labelLarge,
                  ),
                  if (priceHasChanged)
                    Row(
                      children: [
                        Text(
                          Utilities.formatPrice(
                            context,
                            previousRecord.price!,
                            currencyCode: previousRecord.currencyCode,
                          ),
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(Icons.arrow_forward, size: 16),
                        ),
                        Text(
                          Utilities.formatPrice(
                            context,
                            item.price!,
                            currencyCode: item.currencyCode,
                          ),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  else
                    Text(
                      Utilities.formatPrice(
                        context,
                        item.price!,
                        currencyCode: item.currencyCode,
                      ),
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

  Widget _buildInfoRow(
    String label,
    Widget valueWidget, {
    bool alignTop = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: alignTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
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

class OrderHistoryDialog extends StatelessWidget {
  const OrderHistoryDialog({super.key, required this.orderId});
  final int orderId;
  @override
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(OrdersStrings.gridHistory),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: OrderHistoryContent(orderId: orderId),
      ),
    ),
  );
}

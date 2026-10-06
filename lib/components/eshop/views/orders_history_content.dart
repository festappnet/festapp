import '../orders_strings.dart';import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/eshop/db_orders.dart';

import '../models/orders_history_model.dart';

class OrdersHistoryContent extends StatefulWidget {
  const OrdersHistoryContent({super.key});

  @override
  State<OrdersHistoryContent> createState() => _OrdersHistoryContentState();
}

class _OrdersHistoryContentState extends State<OrdersHistoryContent> {
  String? occasionLink;
  SingleDataGridController<OrderHistoryModel>? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink = context.routeData.inheritedPathParams
        .getString(AppRouter.linkFormatted);
    if (occasionLink == null) {
      occasionLink = newOccasionLink;
      _initializeController();
    }
  }

  void _initializeController() {
    if (occasionLink == null) return;

    final newController = SingleDataGridController<OrderHistoryModel>(
      context: context,
      loadData: () async {
        final bundle = await DbOrders.getAllOrdersBundle(
          occasionLink: occasionLink!,
          includeOrdersHistory: true,
          includeOrderDetails: true,
        );

        final List<OrderHistoryModel> allHistoryItems = [];

        for (final order in bundle.orders) {
          final realHistory = order.relatedHistory ?? [];
          for (var h in realHistory) {
            h.orderModel = order;
          }
          allHistoryItems.addAll(realHistory);

          OrderHistoryModel? latestHistoryRecord;
          if (realHistory.isNotEmpty) {
            latestHistoryRecord = realHistory
                .reduce((a, b) => a.createdAt!.isAfter(b.createdAt!) ? a : b);
          }

          bool shouldAddCurrentStateAsHistory = false;
          if (latestHistoryRecord == null) {
            shouldAddCurrentStateAsHistory = true;
          } else {
            if (order.updatedAt != null) {
              final timeDifferenceInSeconds = order.updatedAt!
                  .difference(latestHistoryRecord.createdAt!)
                  .inSeconds;
              if (timeDifferenceInSeconds > 5) {
                if (order.state != latestHistoryRecord.state ||
                    order.price != latestHistoryRecord.price) {
                  shouldAddCurrentStateAsHistory = true;
                }
              }
            }
          }

          if (shouldAddCurrentStateAsHistory) {
            allHistoryItems.add(OrderHistoryModel.fromOrderModel(order));
          }
        }

        final historyByOrder = groupBy(allHistoryItems, (h) => h.orderId);

        for (final orderHistoryList in historyByOrder.values) {
          orderHistoryList.sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
          for (int i = 1; i < orderHistoryList.length; i++) {
            orderHistoryList[i].previousHistoryRecord = orderHistoryList[i - 1];
          }
        }

        allHistoryItems.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

        return allHistoryItems;
      },
      fromPlutoJson: (json) => OrderHistoryModel.fromPlutoJson(json),
      idColumn: EshopColumns.HISTORY_ID,
      actionsExtended: DataGridActionsController(
        isAddActionPossible: () => false,
      ),
      columns: EshopColumns.generateColumns(context, [
        EshopColumns.HISTORY_ID,
        EshopColumns.HISTORY_CHANGED_AT,
        EshopColumns.HISTORY_CHANGED_BY,
        EshopColumns.ORDER_SEQUENCE,
        EshopColumns.HISTORY_ORDER_SYMBOL,
        EshopColumns.ORDER_DATA,
        EshopColumns.ORDER_EMAIL,
        EshopColumns.ORDER_FORM,
        EshopColumns.HISTORY_STATE,
        EshopColumns.HISTORY_PRICE,
        EshopColumns.HISTORY_CHANGES_SUMMARY,
      ]),
      firstColumnType: RightsService.isUnitManager()
          ? DataGridFirstColumn.delete
          : DataGridFirstColumn.check,
    );

    if (mounted) {
      setState(() {
        controller = newController;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<OrderHistoryModel>(controller!);
  }
}

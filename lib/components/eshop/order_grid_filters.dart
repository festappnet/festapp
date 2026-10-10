import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';

import '../single_data_grid/single_data_grid_controller.dart';
import '../single_data_grid/pluto_abstract.dart';
import 'eshop_columns.dart';
import 'models/order_model.dart';
import 'models/orders_history_model.dart';
import 'orders_strings.dart';

class OrderGridFilters {
  static bool orderIsNonCancelled(TrinaRow row) {
    final order =
        row.cells[EshopColumns.ORDER_MODEL_REFERENCE]?.value as OrderModel?;
    final history = row.cells[EshopColumns.HISTORY_MODEL_REFERENCE]?.value
        as OrderHistoryModel?;
    final state = order?.state ??
        history?.orderModel?.state ??
        row.cells[EshopColumns.ORDER_STATE]?.value?.toString().split(';').first;
    return state != OrderModel.stornoState;
  }

  static bool ticketIsNonCancelled(TrinaRow row) =>
      row.cells[EshopColumns.TICKET_STATE]?.value
              ?.toString()
              .split(';')
              .first !=
          OrderModel.stornoState &&
      orderIsNonCancelled(row);

  static Widget filterButton<T extends ITrinaRowModel>(
    BuildContext context,
    SingleDataGridController<T> controller, {
    String? label,
  }) =>
      Semantics(
        toggled: controller.additionalFilterEnabled,
        child: ElevatedButton.icon(
          key: const ValueKey("onlyNonCancelled"),
          onPressed: () => controller
              .toggleAdditionalFilter(!controller.additionalFilterEnabled),
          icon: Icon(
              controller.additionalFilterEnabled
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 18),
          label: Text(
              '${label ?? OrdersStrings.validOrders} (${controller.additionalFilterCount})'),
        ),
      );
}

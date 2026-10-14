import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';

import '../single_data_grid/single_data_grid_controller.dart';
import '../single_data_grid/pluto_abstract.dart';
import 'eshop_columns.dart';
import 'models/order_model.dart';
import 'models/orders_history_model.dart';
import 'orders_strings.dart';

class OrderGridFilters {
  static OrderModel? order(TrinaRow row) =>
      row.cells[EshopColumns.ORDER_MODEL_REFERENCE]?.value as OrderModel?;
  // The canonical deletion command owns cleanup of ordinary and waiting orders.
  // A payment conversion in progress cannot be removed through the grid.
  static bool orderCanBeDeleted(TrinaRow row) {
    final value = order(row);
    return value != null && value.state != 'preparing_payment';
  }

  static bool orderCanReceivePayment(TrinaRow row) =>
      order(row)?.canChangePayment ?? false;

  static bool historyCanBeDeleted(TrinaRow row) =>
      (row.cells[EshopColumns.HISTORY_MODEL_REFERENCE]?.value
              as OrderHistoryModel?)
          ?.isPersisted ??
      false;

  static bool orderIsActive(TrinaRow row) {
    final value = order(row);
    if (value?.isWaitlisted == true) {
      return (value!.waitlistSummary?.counts['offered'] ?? 0) > 0;
    }
    return value?.isActive ?? orderIsNonCancelled(row);
  }

  static bool allows(TrinaRow row, String action) =>
      order(row)?.allows(action) ?? false;

  static String? _orderState(TrinaRow row) {
    final order =
        row.cells[EshopColumns.ORDER_MODEL_REFERENCE]?.value as OrderModel?;
    final history = row.cells[EshopColumns.HISTORY_MODEL_REFERENCE]?.value
        as OrderHistoryModel?;
    return order?.state ??
        history?.orderModel?.state ??
        row.cells[EshopColumns.ORDER_STATE]?.value?.toString().split(';').first;
  }

  static bool orderIsNonCancelled(TrinaRow row) =>
      _orderState(row) != OrderModel.stornoState;

  static bool ticketIsNonCancelled(TrinaRow row) =>
      ![OrderModel.stornoState, OrderModel.waitlistedState].contains(row
          .cells[EshopColumns.TICKET_STATE]?.value
          ?.toString()
          .split(';')
          .first) &&
      ![OrderModel.stornoState, OrderModel.waitlistedState]
          .contains(_orderState(row));

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

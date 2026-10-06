import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';

import '../single_data_grid/single_data_grid_controller.dart';
import '../single_data_grid/pluto_abstract.dart';
import 'eshop_columns.dart';
import 'models/order_model.dart';
import 'orders_strings.dart';

class OrderGridFilters {
  static bool orderIsNonCancelled(TrinaRow row) =>
      (row.cells[EshopColumns.ORDER_MODEL_REFERENCE]?.value as OrderModel?)
          ?.state !=
      OrderModel.stornoState;

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
  }) => FilterChip(
    key: const ValueKey("onlyNonCancelled"),
    selected: controller.additionalFilterEnabled,
    avatar: const Icon(Icons.filter_alt_outlined, size: 18),
    label: Text('${label ?? OrdersStrings.validOrders} (${controller.additionalFilterCount})'),
    onSelected: controller.toggleAdditionalFilter,
    visualDensity: VisualDensity.compact,
  );
}

import 'package:material_ui/material_ui.dart';

import '../_shared/common_strings.dart';
import '../single_data_grid/data_grid_action_confirmation.dart';
import 'models/order_model.dart';
import 'order_item_strings.dart';
import 'order_detail_strings.dart';
import 'orders_strings.dart';

/// One confirmation and item summary for both the grid and order detail.
Future<bool> confirmOrderCancellation(
  BuildContext context,
  List<OrderModel> orders,
) => DataGridActionConfirmation.show<OrderModel>(
  context: context,
  title: OrderItemStrings.cancelAction,
  message:
      '${OrderItemStrings.cancelOrdersConfirmationText}\n\n${OrderDetailStrings.text('cancel_final_warning')}',
  items: orders,
  itemsLabel: OrdersStrings.ordersTab,
  confirmButtonText: OrderItemStrings.cancelAction,
  cancelButtonText: CommonStrings.back,
);

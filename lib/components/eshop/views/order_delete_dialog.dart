import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';
import 'package:fstapp/services/dialog_helper.dart';
import '../db_orders.dart';
import '../models/order_model.dart';
import '../orders_strings.dart';

/// Resolve configuration without exposing the external service credentials.
Future<Future<void> Function(OrderModel)?> prepareOrderDeletion(
    BuildContext context, List<OrderModel> orders) async {
  final eligible = <int>{};
  for (final order in orders) {
    if (await DbOrders.hasFakturoidForDeletion(order.id!)) {
      eligible.add(order.id!);
    }
  }
  if (!context.mounted) return null;
  final deleteInvoice = await showOrderDeleteDialog(context,
      orders: orders, hasFakturoid: eligible.isNotEmpty);
  if (deleteInvoice == null) return null;
  return (order) => DbOrders.deleteOrder(order,
      deleteFakturoidInvoice: deleteInvoice && eligible.contains(order.id));
}

/// null cancels; false deletes only orders; true includes eligible invoices.
Future<bool?> showOrderDeleteDialog(BuildContext context,
    {required List<OrderModel> orders, required bool hasFakturoid}) async {
  var deleteInvoice = false;
  final confirmed = await DialogHelper.showConfirmationDialogRich(
    context: context,
    title: CommonStrings.confirmRemoval,
    confirmButtonText: CommonStrings.delete,
    content: StatefulBuilder(
        builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DataGridActionSummary(
                    items: orders,
                    message: OrdersStrings.deleteOrderNotice,
                  ),
                ),
                if (hasFakturoid)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: deleteInvoice,
                    title: Text(OrdersStrings.deleteFakturoidInvoice),
                    subtitle: Text(OrdersStrings.deleteFakturoidInvoiceHelp),
                    onChanged: (value) =>
                        setState(() => deleteInvoice = value ?? false),
                  ),
              ],
            )),
  );
  return confirmed ? deleteInvoice : null;
}

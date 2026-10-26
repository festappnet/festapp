import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'db_orders.dart';
import 'db_eshop.dart';
import 'ticket_commands.dart';
import 'orders_strings.dart';
import 'views/order_update_email_dialog.dart';

Future<bool> confirmCancelledOrderEmail(BuildContext context, String email) =>
    DialogHelper.showConfirmationDialog(
      context,
      'FeatureOrders.cancellationEmailTitle'.tr(),
      'FeatureOrders.cancellationEmailQuestion'.tr(namedArgs: {'email': email}),
      confirmButtonMessage: OrdersStrings.sendEmailButton,
      cancelButtonMessage: 'FeatureOrders.skipCancellationEmail'.tr(),
    );

/// Both cancellation entry points offer optional email after the mutation.
/// The order state is authoritative even when the user skips notification.
Future<void> showTicketCancellationUpdates(
    BuildContext context, TicketCancellationOutcome outcome) async {
  for (final id in outcome.cancelledOrderIds) {
    if (!context.mounted) return;
    final history = await ExceptionHandler.guard<OrderHistoryBundle?>(
      context,
      defaultErrorMessage: OrdersStrings.sendEmailFailed,
      futureFunction: () => DbOrders.getOrderHistory(id),
    );
    if (history == null || !context.mounted) continue;
    final email = history.order.data?['email'] as String? ?? '';
    if (email.trim().isEmpty) continue;
    final send = await confirmCancelledOrderEmail(context, email);
    if (!send || !context.mounted) continue;
    await DialogHelper.showProgressDialogAsync(
      context,
      OrdersStrings.processing,
      1,
      futures: [
        () async {
          await DbOrders.sendStornoTicketOrderEmail(orderId: id);
        }
      ],
    );
  }
  for (final order in outcome.updatedOrders) {
    if (!context.mounted) return;
    if (order.email.trim().isEmpty) continue;
    // Resolve a surviving ticket through existing order/detail RPCs so the
    // preview uses the same sent-history baseline as product editing.
    final bundle = await ExceptionHandler.guard<TicketDetailsBundle?>(
      context,
      defaultErrorMessage: OrdersStrings.sendEmailFailed,
      futureFunction: () async {
        final history = await DbOrders.getOrderHistory(order.id);
        final tickets = history.order.data?['tickets'] as List? ?? [];
        if (tickets.isEmpty) return null;
        return DbEshop.getProductsForTicket(
          (tickets.first as Map<String, dynamic>)['id'] as int,
        );
      },
    );
    if (bundle == null || !context.mounted) continue;
    final send = await showOrderUpdateEmailDialog(
      context,
      email: order.email,
      changes: bundle.changes,
      ticketId: bundle.ticket.id!,
      balance: (bundle.order.price ?? 0) - (bundle.paymentInfo?.paid ?? 0),
    );
    if (!send || !context.mounted) continue;
    final sent = await DialogHelper.showProgressDialogAsync(
      context,
      OrdersStrings.processing,
      1,
      futures: [
        () async {
          await DbEshop.sendTicketOrderUpdateEmail(order.id);
        },
      ],
    );
    if (context.mounted && sent) {
      ToastHelper.Show(context, OrdersStrings.sendEmailSuccess);
    }
  }
}

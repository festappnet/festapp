import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import '../logic/order_calc_helper.dart';
import '../orders_strings.dart';
import 'product_changes_preview.dart';

/// Shared preview for product edits and ticket cancellations.
Future<bool> showOrderUpdateEmailDialog(
  BuildContext context, {
  required String email,
  required OrderCalcHelper changes,
  required double balance,
}) async {
  return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(OrdersStrings.sendUpdateTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(OrdersStrings.sendUpdateContent(email)),
                    const Divider(height: 24),

                    Text(OrdersStrings.emailContentIntro,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic)),
                    const SizedBox(height: 12),
                    ProductChangesPreview(
                      added: changes.added,
                      removed: changes.removed,
                      changed: changes.changed,
                      referenceTotal: changes.referenceTotal,
                      currentTotal: changes.currentTotal,
                    ),
                    // Only show the note if there are changes from other tickets
                    if (changes.hasChangesFromOtherTickets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.orange.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                OrdersStrings.globalChangesNote,
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ProductChangesPreview.buildConfirmationListItem(context,
                        Icons.credit_card, OrdersStrings.sendUpdateItemStatus),
                    if (balance < 0)
                      ProductChangesPreview.buildConfirmationListItem(
                          context,
                          Icons.undo_outlined,
                          OrdersStrings.sendUpdateItemRefund),
                    ProductChangesPreview.buildConfirmationListItem(
                        context,
                        Icons.receipt_long_outlined,
                        OrdersStrings.sendUpdateItemSummary),
                    if (balance > 0)
                      ProductChangesPreview.buildConfirmationListItem(context,
                          Icons.qr_code_2, OrdersStrings.sendUpdateItemQr),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(CommonStrings.storno)),
                ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(OrdersStrings.sendEmailButton)),
              ],
            );
          }) ??
      false;
}

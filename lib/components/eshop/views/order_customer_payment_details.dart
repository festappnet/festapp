import 'package:material_ui/material_ui.dart';

import '../../../services/payment_deadline.dart';
import '../../../services/utilities_all.dart';
import '../../_shared/copy_button.dart';
import '../../bank_accounts/bank_account_strings.dart';
import '../../forms/form_strings.dart';
import '../../forms/order_overview_strings.dart';
import '../../forms/public_order_strings.dart';

/// Bank destination metadata from the authorized order reader, including paid
/// orders. Reading this widget never creates instructions or a payment intent.
class OrderCustomerPaymentDetails extends StatelessWidget {
  const OrderCustomerPaymentDetails({
    super.key,
    required this.details,
    required this.payment,
    required this.currencyCode,
  });
  final Map<String, dynamic> details, payment;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    if (details.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    String? text(String key) {
      final value = details[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final account = text('account');
    final iban = text('iban');
    final reference = text('reference');
    final creditor = text('creditorName');
    final due = payment['dueNow'];
    final knownAmount =
        due is num &&
        due.isFinite &&
        due > 0 &&
        !const {
          'unknown',
          'cancelled',
          'fully_paid',
          'paid',
        }.contains(payment['status']);
    // Match the existing transaction detail rows: compact body text and a
    // consistent label/value split, with natural wrapping at narrow widths.
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 14);
    Widget fact(
      String label,
      String value, {
      bool copy = false,
    }) => LayoutBuilder(
      builder: (context, constraints) {
        // Reserve the stacked fallback for narrow panes with enlarged text.
        // Ordinary mobile and desktop keep the canonical compact columns.
        final stacked =
            constraints.maxWidth < 340 &&
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(top: copy ? 5 : 0),
                child: Text(value, style: bodyStyle),
              ),
            ),
            if (copy) ...[const SizedBox(width: 4), CopyButton(value: value)],
          ],
        );
        return Padding(
          padding: EdgeInsets.only(bottom: stacked ? 10 : 5),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$label:', style: bodyStyle),
                    content,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: EdgeInsets.only(top: copy ? 5 : 0, right: 8),
                        child: Text('$label:', style: bodyStyle),
                      ),
                    ),
                    Expanded(flex: 5, child: content),
                  ],
                ),
        );
      },
    );
    return SelectionArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FormStrings.paymentDetailsTitle,
              style: bodyStyle?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (creditor != null)
              fact(BankAccountStrings.creditorNameLabel, creditor),
            if (account != null)
              fact(PublicOrderStrings.bankAccount, account, copy: true),
            if (iban != null && iban != account)
              fact(PublicOrderStrings.iban, iban, copy: true),
            if (reference != null)
              fact(
                details['referenceKind'] == 'RF'
                    ? PublicOrderStrings.paymentReference
                    : PublicOrderStrings.variableSymbol,
                reference,
                copy: true,
              ),
            if (knownAmount)
              fact(
                PublicOrderStrings.amountToPay,
                Utilities.formatPrice(
                  context,
                  due.toDouble(),
                  currencyCode: currencyCode,
                  decimalDigits: 2,
                ),
              ),
            if (payment['dueAt'] != null)
              fact(
                OrderOverviewStrings.text('dueAt'),
                PaymentDeadline.format(
                  payment['dueAt'],
                  Localizations.localeOf(context).toString(),
                ),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

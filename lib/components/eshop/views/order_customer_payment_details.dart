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
        due >= 0 &&
        !const {'unknown', 'cancelled'}.contains(payment['status']);
    Widget fact(String label, String value, {bool copy = false}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(value, style: theme.textTheme.bodyLarge),
              ),
              if (copy) CopyButton(value: value),
            ],
          );
          final heading = Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
          return constraints.maxWidth < 480
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 3), content],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 170, child: heading),
                    const SizedBox(width: 16),
                    Expanded(child: content),
                  ],
                );
        },
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            FormStrings.paymentDetailsTitle,
            style: theme.textTheme.titleMedium,
          ),
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
          const SizedBox(height: 16),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

import 'package:festapp_core/eshop.dart';

import 'transaction_model.dart';

/// Recipient choices come only from active incoming bank facts for this payment.
/// Historical bank imports keep their original `legacy` provenance.
class PaymentRefundRecipient {
  const PaymentRefundRecipient({required this.iban, required this.name});

  final String iban, name;

  static List<PaymentRefundRecipient> fromTransactions(
    List<TransactionModel> transactions,
    String currency,
  ) {
    final recipients = <String, PaymentRefundRecipient>{};
    for (final transaction in transactions) {
      if (transaction.voided ||
          transaction.isRefund ||
          (transaction.amount ?? 0) <= 0 ||
          transaction.currency?.trim() != currency ||
          !const {
            'banksync_api',
            'fio_api',
            'legacy',
          }.contains(transaction.ingestSource)) {
        continue;
      }
      final iban = _incomingIban(transaction, currency);
      if (iban == null) continue;
      final name = transaction.counterAccountName?.trim() ?? '';
      if (!recipients.containsKey(iban) || recipients[iban]!.name.isEmpty) {
        recipients[iban] = PaymentRefundRecipient(iban: iban, name: name);
      }
    }
    return List.unmodifiable(recipients.values);
  }

  static String? _incomingIban(TransactionModel transaction, String currency) {
    final account = (transaction.counterAccount ?? '')
        .replaceAll(RegExp(r'\s'), '')
        .toUpperCase();
    if (IbanUtils.isValidIban(account)) return account;

    // A bare domestic number has no country identity outside the CZK path.
    if (currency != 'CZK') return null;
    final domestic = RegExp(r'^(?:(\d{1,6})-)?(\d{1,10})(?:/(\d{4}))?$')
        .firstMatch(account);
    if (domestic == null) return null;
    final bank = domestic.group(3) ?? transaction.bankCode?.trim();
    if (bank == null) return null;
    try {
      return IbanUtils.generateCzIban(
        bank,
        domestic.group(1) ?? '',
        domestic.group(2)!,
      );
    } on FormatException {
      return null;
    }
  }
}

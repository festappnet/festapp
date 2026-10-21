import 'package:intl/intl.dart';

/// Display-only inputs. These never create an order or enter template storage.
class EmailPreviewProduct {
  final String title, typeTitle, currency;
  final double price;
  const EmailPreviewProduct({
    required this.title,
    required this.typeTitle,
    required this.price,
    this.currency = 'CZK',
  });
}

/// Configured payment destination used only as a display example.
class EmailPreviewPaymentAccount {
  final String accountNumber, iban;
  final List<String> currencies;
  const EmailPreviewPaymentAccount({
    required this.accountNumber,
    required this.iban,
    required this.currencies,
  });
}

class EmailPreviewContext {
  final String? occasionTitle, deadline;
  final EmailPreviewPaymentAccount? paymentAccount;
  final bool? ticketsEnabled;
  final bool? blueprintEnabled;
  bool get singleApplication =>
      ticketsEnabled == false && blueprintEnabled != true;
  final List<EmailPreviewProduct> products;
  const EmailPreviewContext({
    this.occasionTitle,
    this.deadline,
    this.ticketsEnabled,
    this.blueprintEnabled,
    this.paymentAccount,
    this.products = const [],
  });

  EmailPreviewContext withPaymentAccount(EmailPreviewPaymentAccount? account) =>
      EmailPreviewContext(
        occasionTitle: occasionTitle,
        deadline: deadline,
        ticketsEnabled: ticketsEnabled,
        blueprintEnabled: blueprintEnabled,
        products: products,
        paymentAccount: account ?? paymentAccount,
      );

  Map<String, String> bindings({required bool zero}) {
    final paymentBindings = {
      if (paymentAccount != null)
        'preview_account_number': paymentAccount!.accountNumber,
      if (paymentAccount != null) 'preview_iban': paymentAccount!.iban,
    };
    if (products.isEmpty)
      return {
        ...paymentBindings,
        if (occasionTitle != null) 'preview_occasion': occasionTitle!,
        if (deadline != null) 'preview_deadline': deadline!,
      };
    final first = products.first;
    final second = !singleApplication && products.length > 1
        ? products[1]
        : first;
    final total = zero
        ? 0.0
        : first.price + (singleApplication ? 0 : second.price);
    // Explicitly fictional deposit/history examples, never payment computation.
    final deposit = (total * .375 * 100).roundToDouble() / 100;
    final previousSecond = zero
        ? 0.0
        : (second.price * (5 / 7) * 100).roundToDouble() / 100;
    String money(double value) => NumberFormat.simpleCurrency(
      locale: 'cs_CZ',
      name: first.currency,
      decimalDigits: value == value.roundToDouble() ? 0 : 2,
    ).format(value);
    return {
      ...paymentBindings,
      if (occasionTitle != null) 'preview_occasion': occasionTitle!,
      if (deadline != null) 'preview_deadline': deadline!,
      'preview_product_0_title': first.title,
      'preview_product_0_type': first.typeTitle,
      'preview_product_1_title': second.title,
      'preview_product_1_type': second.typeTitle,
      'preview_price_0': money(zero ? 0 : first.price),
      'preview_price_1': money(zero ? 0 : second.price),
      'preview_total': money(total),
      'preview_deposit': money(deposit),
      'preview_remaining': money(total - deposit),
      'preview_previous_price': money(previousSecond),
      'preview_reference_total': money(
        zero ? 0 : (singleApplication ? 0 : first.price) + previousSecond,
      ),
      'preview_zero': money(0),
      'preview_zero_explanation': '0 ${first.currency}',
      'preview_currency': first.currency,
    };
  }
}

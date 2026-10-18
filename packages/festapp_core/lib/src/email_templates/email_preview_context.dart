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

class EmailPreviewContext {
  final String? occasionTitle, deadline;
  final List<EmailPreviewProduct> products;
  const EmailPreviewContext({
    this.occasionTitle,
    this.deadline,
    this.products = const [],
  });

  Map<String, String> bindings({required bool zero}) {
    if (products.isEmpty)
      return {
        if (occasionTitle != null) 'preview_occasion': occasionTitle!,
        if (deadline != null) 'preview_deadline': deadline!,
      };
    final first = products.first;
    final second = products.length > 1 ? products[1] : first;
    final total = zero ? 0.0 : first.price + second.price;
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
      if (occasionTitle != null) 'preview_occasion': occasionTitle!,
      'preview_deadline': deadline ?? '30. 10. 2026',
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
      'preview_reference_total': money(zero ? 0 : first.price + previousSecond),
      'preview_zero': money(0),
      'preview_zero_explanation': '0 ${first.currency}',
      'preview_currency': first.currency,
    };
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/widgets_view/form_total_price.dart';

void main() {
  for (final stripe in [false, true]) {
    for (final currency in ['CZK', 'EUR']) {
      testWidgets(
          'floating $currency total keeps ${stripe ? 'Stripe cents' : 'legacy bank rounding'}',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: FormTotalPrice(
          amount: 98.76,
          currencyCode: currency,
          payments: stripe
              ? {
                  'configured': {'stripe': true},
                  'available': []
                }
              : null,
        ))));
        final text = tester
            .widget<Text>(find.descendant(
                of: find.byType(FormTotalPrice), matching: find.byType(Text)))
            .data!;
        expect(text, contains(stripe ? '98,76' : '99'));
        if (stripe) expect(text, isNot(contains('99')));
      });
    }
  }
}

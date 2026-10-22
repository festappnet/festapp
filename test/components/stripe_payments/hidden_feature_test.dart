import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/stripe_payments/stripe_feature.dart';
import 'package:fstapp/components/stripe_payments/unit_card_payments_page.dart';
import 'package:fstapp/main.dart' as app;

void main() {
  testWidgets('default build hides the direct card settings route before loading account data', (tester) async {
    expect(StripeFeature.visible, isFalse);
    await tester.pumpWidget(const MaterialApp(home: UnitCardPaymentsPage()));
    expect(find.byType(UnitCardPaymentsView), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('private Stripe startup routes bypass default occasion loading and strip payment credentials', () {
    expect(AppRouter.getRootLinks(), contains('stripe'));
    for (final path in ['/stripe/pay', '/stripe/return', '/app/stripe/pay', '/app/stripe/return', '/stripe/connect/callback', '/app/stripe/connect/callback']) {
      expect(app.isUnitAdminStartupRoute(Uri.parse(path)), isTrue);
    }
    expect(app.nativeInitialRoute('/app/stripe/pay#pay=private'), '/stripe/pay');
    expect(app.nativeInitialRoute('/stripe/return?return_handle=private'), '/stripe/return');
  });
}

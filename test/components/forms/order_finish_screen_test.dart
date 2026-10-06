import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/components/forms/views/order_finish_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
      'queued confirmation renders before acceptance and status failure never claims sent',
      (tester) async {
    for (final fail in [false, true]) {
      final status = Completer<String?>();
      await tester.pumpWidget(MaterialApp(
          home: FinishOrderScreen(
              key: ValueKey(fail),
              hasTickets: false,
              orderFutureFunction: () async => const FunctionResponse(data: {
                    'code': 200,
                    'delivery_receipt': 'opaque',
                    'ticketOrder': {
                      'order': {
                        'order_symbol': '7G4K9M2R6A',
                        'data': {'email': 'fixture@example.invalid'}
                      }
                    }
                  }, status: 200),
              deliveryStatusReader: (_) => status.future)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      expect(
          find.text(PublicOrderStrings.confirmationInfo(null,
              hasPayment: false,
              email: 'fixture@example.invalid',
              state: 'queued')),
          findsOneWidget);
      expect(find.textContaining('7G4K9M2R6A'), findsOneWidget);
      if (fail) {
        status.completeError(Exception('endpoint unavailable'));
      } else {
        status.complete('accepted');
      }
      await tester.pumpAndSettle();
      expect(
          find.text(PublicOrderStrings.confirmationInfo(null,
              hasPayment: false,
              email: 'fixture@example.invalid',
              state: fail ? 'queued' : 'accepted')),
          findsOneWidget);
    }
  });

  testWidgets('order submission always transitions from progress to success',
      (tester) async {
    final response = Completer<FunctionResponse>();

    await tester.pumpWidget(
      MaterialApp(
        home: FinishOrderScreen(
          orderFutureFunction: () => response.future,
          hasTickets: false,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    response.complete(const FunctionResponse(
      data: {'code': 200},
      status: 200,
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text(PublicOrderStrings.successTitle(null, hasTickets: false)),
        findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text(PublicOrderStrings.backToForm), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

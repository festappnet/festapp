import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/components/forms/views/order_finish_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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

import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/components/forms/views/order_finish_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets(
      'overview close notifies once after route pop so the preview can close',
      (tester) async {
    var closed = 0;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showGeneralDialog(
                    context: context,
                    pageBuilder: (dialogContext, _, __) => FinishOrderScreen(
                          overviewAvailable: true,
                          orderFutureFunction: () async =>
                              const FunctionResponse(
                                  status: 200, data: {'code': 200}),
                          onSuccess: () {
                            closed++;
                          },
                        )),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OrderOverview.title'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.byType(FinishOrderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'queued confirmation renders before acceptance and status failure never claims sent',
      (tester) async {
    for (final fail in [false, true]) {
      final status = Completer<String?>();
      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
      MaterialApp(builder: DependencyMaterialBridge.builder,
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

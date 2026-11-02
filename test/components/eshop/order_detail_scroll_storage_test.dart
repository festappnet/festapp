import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/eshop/views/order_email_repair_dialog.dart';

import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  testWidgets(
    'expanded contact details cannot overwrite the detail scroll offset during layout replacement',
    (tester) async {
      final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
      addTearDown(logs.dispose);
      final bucket = PageStorageBucket();
      Future<dynamic> read(String name, Map<String, dynamic> args) async =>
          name == 'get_order_history'
          ? {
              'code': 200,
              'data': {
                'order': {
                  'id': 9,
                  'occasion': 7,
                  'state': 'ordered',
                  'email_payment_version': 1,
                  'email_payment_fingerprint': 'facts',
                  'data': {'name': 'Klára', 'email': 'host6@example.invalid'},
                },
              },
            }
          : {
              'current_issues': [
                {
                  'message_id': 'local-message',
                  'source_message_id': 'local-message',
                  'kind': 'order_confirmation',
                  'state': 'bounce',
                  'recipient': 'host6@example.invalid',
                  'original_recipient': 'host6@example.invalid',
                },
              ],
            };
      Widget host(int layout) => MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: KeyedSubtree(
              key: ValueKey(layout),
              child: SizedBox(
                width: 600,
                height: 400,
                child: SingleChildScrollView(
                  key: const PageStorageKey('order-9-overview'),
                  child: OrderEmailContactEditor(
                    orderId: 9,
                    occasionId: 7,
                    read: read,
                    canWrite: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(0));
      await tester.pumpAndSettle();
      final details = find.text('EmailDelivery.recovery.details');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(1));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Expansion bool must not be read as a saved double scroll offset',
      );
      expect(find.byType(TextField), findsOneWidget);
    },
  );
}

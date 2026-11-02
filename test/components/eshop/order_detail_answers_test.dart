import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/models/order_admin_detail.dart';
import 'package:fstapp/components/eshop/views/order_detail_answers.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets(
    'order answers exclude unsupported ticket fields and retain configured scope',
    (tester) async {
      final ticket = <String, dynamic>{
        'id': 42,
        'data': {
          'fields': [
            {'10': 'Window seat'},
            {'12': 'Morning'},
          ],
        },
        'snapshot': {
          'products': [
            {'id': 22, 'title': 'Purchased workshop', 'price': 100},
          ],
        },
      };
      final detail = OrderAdminDetail({
        'fields': [
          {
            'id': 10,
            'title': 'Your request',
            'type': 'text',
            'is_ticket_field': true,
            'order': 3,
          },
          {
            'id': 11,
            'type': 'product_type',
            'product_type': 4,
            'product_type_data': {'id': 4, 'title': 'Configured workshop'},
            'is_ticket_field': true,
            'order': 1,
          },
          {
            'id': 12,
            'title': 'Session',
            'type': 'select_one',
            'data': {
              'options': [
                {'value': 'Morning'},
                {'value': 'Afternoon'},
              ],
            },
            'is_ticket_field': true,
            'order': 2,
          },
          {
            'id': 13,
            'title': 'Organization',
            'type': 'text',
            'is_ticket_field': false,
            'order': 0,
          },
          {
            'id': 14,
            'title': 'Structural seat selector',
            'type': 'spot',
            'is_ticket_field': true,
            'order': 0,
          },
        ],
        'productCategories': {'22': 4},
        'tickets': [ticket],
        'answers': [
          {'13': 'Local club'},
        ],
      });
      final environment = WidgetEnvironmentFixture(
        locale: const Locale('en'),
        translations: jsonDecode(
          File('assets/translations/en.json').readAsStringSync(),
        ),
      );
      Future<void> show() async {
        await environment.pumpWidget(
          tester,
          MaterialApp(
            home: Scaffold(body: OrderDetailAnswers(detail: detail)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      expect(find.text('Your request'), findsNothing);
      expect(find.text('Session'), findsNothing);
      expect(find.text('Morning'), findsNothing);
      expect(find.text('Window seat'), findsNothing);
      expect(find.text('Structural seat selector'), findsNothing);
      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Local club'), findsOneWidget);
      expect(find.text('Configured workshop'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

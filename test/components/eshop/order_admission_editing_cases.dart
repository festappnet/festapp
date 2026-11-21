import 'dart:convert';
import 'dart:io';

import 'package:festapp_core/eshop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/views/order_admission_dialog.dart';
import 'package:fstapp/components/eshop/views/products_dialog.dart';
import 'package:fstapp/components/eshop/views/search_products_screen.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  final environment = WidgetEnvironmentFixture(
    locale: const Locale('en'),
    translations: jsonDecode(
      File('assets/translations/en.json').readAsStringSync(),
    ),
  );
  Future<void> open(WidgetTester tester, Widget child) async {
    await environment.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  final seat = ProductModel(
    id: 1,
    title: 'Balcony A1',
    productTypeString: 'spot',
    price: 500,
  );
  final standing = ProductModel(
    id: 2,
    title: 'Standing',
    productTypeString: 'spot',
    price: 400,
  );
  final meal = ProductModel(
    id: 3,
    title: 'Dinner',
    productTypeString: 'food',
    price: 100,
  );
  testWidgets('Product picker exposes only add-ons with a known catalog type', (
    tester,
  ) async {
    await open(
      tester,
      SearchProductsScreen(
        ticketId: 1,
        alreadySelected: [seat],
        loadProducts: (_) async => [
          seat,
          standing,
          meal,
          ProductModel(id: 4, title: 'Unknown'),
          ProductModel(id: 5, productTypeId: 8, title: 'Parking'),
        ],
      ),
    );
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Parking'), findsOneWidget);
    for (final title in ['Balcony A1', 'Standing', 'Unknown']) {
      expect(find.text(title), findsNothing);
    }
  });
  for (final multiple in [false, true]) {
    testWidgets(
      'Stored admission price stays visible and protected with multiple=$multiple',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(950, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bundle = TicketDetailsBundle(
          order: OrderModel(
            state: 'ordered',
            allowedActions: {'view', 'edit'},
            price: 500,
          ),
          ticket: TicketModel(
            id: 1,
            state: 'ordered',
            relatedProducts: [seat, if (multiple) standing],
          ),
          orderHistory: OrderHistoryInfo(isNewerVersionAvailable: false),
          changes: OrderChangeSummary.fromJson({
            'version': 1,
            'hasChanges': false,
            'referenceTotal': 500,
            'currentTotal': 500,
            'currencyCode': 'CZK',
            'cancelledTickets': [],
            'removedTickets': [],
            'addedTickets': [],
            'productChanges': [],
          }),
          admission: {
            'spotCount': multiple ? 2 : 1,
            'recordedPlaces': ['A1'],
          },
        );
        await open(
          tester,
          ProductsDialog(ticketId: 1, loadTicket: (_) async => bundle),
        );
        expect(find.text('Balcony A1'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        expect(
          find.byIcon(Icons.edit_outlined),
          multiple ? findsNothing : findsOneWidget,
        );
        if (multiple) {
          expect(find.text('Standing'), findsOneWidget);
          expect(find.text('Recorded place: A1'), findsOneWidget);
          expect(
            find.textContaining('contains multiple admissions'),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.add_shopping_cart), findsNothing);
        }
      },
    );
  }
  testWidgets(
    'Whole-unit admission needs separate visitor answers and fresh preview after conflict',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <String>[];
      final title = 'Add ticket';
      await open(
        tester,
        OrderAdmissionDialog(
          orderId: 10,
          ticketTerminology: true,
          title: title,
          currency: 'CZK',
          money: (n) => '$n CZK',
          canWrite: () => true,
          rpc: (name, args) async {
            calls.add(name);
            if (name.startsWith('get_'))
              return {
                'code': 200,
                'data': {
                  'options': [
                    {
                      'productId': 2,
                      'spotId': 4,
                      'title': 'Table 4',
                      'quantity': 2,
                    },
                  ],
                  'fields': [
                    {
                      'id': 123,
                      'type': 'name',
                      'title': 'Visitor name',
                      'required': true,
                    },
                  ],
                },
              };
            if (name.startsWith('preview_')) {
              expect(args['p_answers'], [
                [
                  {'_subFieldId': '123', 'name': 'Anna'},
                ],
                [
                  {'_subFieldId': '123', 'name': 'David'},
                ],
              ]);
              return {
                'code': 200,
                'data': {
                  'targetTitle': 'Table 4',
                  'quantity': 2,
                  'ticketCount': 3,
                  'priceDelta': 800,
                  'total': 1300,
                  'balance': 800,
                  'fingerprint': 'first',
                },
              };
            }
            return {
              'code': 409,
              'data': {'reason': 'ORDER_CHANGED_RELOAD_REQUIRED'},
            };
          },
        ),
      );
      await tester.tap(find.text('Review change'));
      await tester.pumpAndSettle();
      expect(calls, ['get_order_admission_options_v1']);
      final inputs = find.byType(EditableText);
      await tester.enterText(inputs.at(0), 'Anna');
      await tester.enterText(inputs.at(1), 'David');
      await tester.ensureVisible(find.text('Review change'));
      await tester.tap(find.text('Review change'));
      await tester.pumpAndSettle();
      expect(find.text('3 tickets'), findsOneWidget);
      final confirm = find.text('Add the entire group (2 tickets)');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Reload the available admissions'),
        findsOneWidget,
      );
      expect(confirm, findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls.last, 'get_order_admission_options_v1');
      expect(calls.where((n) => n.startsWith('confirm_')).length, 1);
    },
  );
  for (final move in [false, true]) {
    testWidgets(
      'Admission preview binds the reviewed change and confirmation identity move=$move',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(720, 1250));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final commands = <Map<String, dynamic>>[];
        final title = move ? 'Change admission type' : 'Add ticket';
        await open(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => OrderAdmissionDialog(
                  orderId: 10,
                  ticketId: move ? 20 : null,
                  ticketTerminology: true,
                  title: title,
                  canWrite: () => true,
                  currency: 'CZK',
                  money: (n) => '$n CZK',
                  rpc: (name, args) async {
                    expect(args['p_ticket_id'], move ? 20 : null);
                    if (name.startsWith('get_'))
                      return {
                        'code': 200,
                        'data': {
                          'options': [
                            {
                              'productId': 2,
                              'title': 'Standing',
                              'quantity': 1,
                            },
                          ],
                          'fields': [],
                        },
                      };
                    expect(args['p_target'], {'productId': 2, 'spotId': null});
                    expect(args['p_answers'], isEmpty);
                    if (name.startsWith('preview_'))
                      return {
                        'code': 200,
                        'data': {
                          'fingerprint': 'original',
                          'sourceTitle': 'Balcony A1',
                          'targetTitle': 'Standing',
                          'quantity': 1,
                          'ticketCount': move ? 1 : 2,
                          'priceDelta': move ? -100 : 400,
                          'total': move ? 400 : 900,
                          'balance': move ? -100 : 400,
                        },
                      };
                    commands.add(args);
                    if (commands.length == 1)
                      throw const SocketException('lost response');
                    return {
                      'code': 200,
                      'data': {'ticketId': 21},
                    };
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review change'));
        await tester.pumpAndSettle();
        expect(commands, isEmpty);
        expect(find.text(move ? '400 CZK' : '900 CZK'), findsOneWidget);
        if (move) expect(find.text('Balcony A1'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, title));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Recover result'));
        await tester.pumpAndSettle();
        expect(commands.length, 2);
        expect(commands.last, commands.first);
        expect(commands.first['p_fingerprint'], 'original');
        expect(commands.first['p_command_id'], isA<String>());
        expect(find.byType(OrderAdmissionDialog), findsNothing);
      },
    );
  }
}

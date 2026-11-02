import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/order_detail_controller.dart';
import 'package:fstapp/components/eshop/models/order_admin_detail.dart';
import 'package:fstapp/components/eshop/views/order_detail_answers.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_strings.dart';
import 'package:fstapp/components/eshop/views/order_detail_view.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();

  Future<void> open(
    WidgetTester tester, {
    required String language,
    int count = 1,
    bool ticketsEnabled = true,
    bool issuanceHidden = false,
    int maximum = 10,
    List<Map<String, dynamic>> extraFields = const [],
    List<Map<String, dynamic>> answers = const [],
    String tab = 'overview',
    bool writable = false,
    bool canCancel = false,
    Size size = const Size(1000, 1400),
    VoidCallback? onClose,
  }) async {
    await tester.binding.setSurfaceSize(size);
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: OccasionModel(
        id: 71,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        features: [SimpleFeature(code: 'ticket', isEnabled: ticketsEnabled)],
      ),
    );
    final controller = OrderDetailController(
      orderId: 42,
      occasionId: 71,
      read: (name, args) async {
        expect(name, 'get_order_admin_detail');
        expect(args, {'p_order': 42, 'p_occasion': 71});
        return {
          'code': 200,
          'data': {
            'order': {
              'id': 42,
              'occasion': 71,
              'form_id': 88,
              'order_symbol': 'ORD-42',
              'state': 'ordered',
              'price': 400,
              'currency_code': 'CZK',
              'allowedActions': [if (writable) 'edit', if (canCancel) 'cancel'],
              'data': {'name': 'Alex', 'email': 'alex@example.com'},
            },
            'capabilities': {'write': writable},
            'payment': {
              'status': 'known',
              'received': 0,
              'totalOutstanding': 400,
            },
            'emailSummary': <String, dynamic>{},
            'answers': answers,
            'fields': [
              ...extraFields,
              {
                'id': 91,
                'type': 'ticket',
                'is_hidden': issuanceHidden,
                'data': {'max_tickets': maximum},
              },
            ],
            'tickets': [
              for (var i = 0; i < count; i++)
                {
                  'id': 100 + i,
                  'ticket_symbol': ticketsEnabled && !issuanceHidden
                      ? 'T-${100 + i}'
                      : null,
                  'state': 'ordered',
                  'snapshot': {
                    'products': [
                      {'id': 501, 'title': 'Historical supper', 'price': 125},
                      {'id': 501, 'title': 'Historical supper', 'price': 275},
                    ],
                  },
                },
            ],
            'places': <dynamic>[],
            'plans': <dynamic>[],
            'placementFingerprint': 'presentation-fixture',
          },
        };
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      RightsService.occasionLinkModelNotifier.value = previous;
      await tester.binding.setSurfaceSize(null);
    });
    expect(await controller.load(), isTrue);
    final environment = WidgetEnvironmentFixture(
      locale: Locale(language),
      translations: jsonDecode(
        File('assets/translations/$language.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    await environment.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: OrderDetailView(
            controller: controller,
            tab: tab,
            onTab: (_) {},
            onClose: () async => onClose?.call(),
            onChanged: () async {},
            onPrevious: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in ['cs', 'en']) {
    final expectedTickets = language == 'cs'
        ? {
            0: '0 vstupenek',
            1: '1 vstupenka',
            2: '2 vstupenky',
            5: '5 vstupenek',
          }
        : {0: '0 tickets', 1: '1 ticket', 2: '2 tickets', 5: '5 tickets'};
    final expectedApplications = language == 'cs'
        ? {
            0: '0 přihlášek',
            1: '1 přihláška',
            2: '2 přihlášky',
            5: '5 přihlášek',
          }
        : {
            0: '0 applications',
            1: '1 application',
            2: '2 applications',
            5: '5 applications',
          };
    for (final tickets in [true, false]) {
      for (final count in [0, 1, 2, 5]) {
        testWidgets(
          '$language overview labels $count ${tickets ? 'tickets' : 'applications'} correctly',
          (tester) async {
            await open(
              tester,
              language: language,
              count: count,
              ticketsEnabled: tickets,
            );
            final countLabel = (tickets
                ? expectedTickets
                : expectedApplications)[count]!;
            final placesLabel = language == 'cs'
                ? '0 přiřazených míst'
                : '0 assigned places';
            expect(find.text('$countLabel · $placesLabel'), findsOneWidget);
            expect(
              find.text(
                language == 'cs' ? 'Obsah objednávky' : 'Order contents',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'single application preserves repeated historical product instances and exposes one editor',
    (tester) async {
      await open(
        tester,
        language: 'en',
        ticketsEnabled: false,
        maximum: 1,
        writable: true,
      );
      expect(find.text('Historical supper'), findsNWidgets(2));
      final rows = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where(
            (row) =>
                row.title is Text &&
                (row.title as Text).data == 'Historical supper',
          )
          .toList();
      expect(rows, hasLength(2));
      expect((rows[0].trailing as Text).data, contains('125'));
      expect((rows[1].trailing as Text).data, contains('275'));
      expect(find.text('Application 100'), findsNothing);
      expect(find.text('Edit products'), findsOneWidget);
      expect(find.text('Applications and places'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden issuance container presents multiple applications even with ticket feature enabled',
    (tester) async {
      await open(
        tester,
        language: 'en',
        count: 2,
        issuanceHidden: true,
        maximum: 2,
      );
      expect(find.text('Application 100'), findsOneWidget);
      expect(find.text('Application 101'), findsOneWidget);
      expect(find.text('Historical supper'), findsNWidgets(4));
      expect(find.text('2 applications · 0 assigned places'), findsOneWidget);
      expect(find.text('Edit products'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile navigation stays beside close and expand is absent', (
    tester,
  ) async {
    var closed = 0;
    await open(
      tester,
      language: 'en',
      size: const Size(360, 800),
      onClose: () => closed++,
    );
    final close = find.byIcon(Icons.close);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
    expect(find.byIcon(Icons.close_fullscreen), findsNothing);
    final previous = find.byIcon(Icons.chevron_left);
    expect(tester.getTopLeft(close).dy, tester.getTopLeft(previous).dy);
    expect(tester.getBottomRight(close).dx, lessThanOrEqualTo(360));
    await tester.tap(close);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['cs', 'en']) {
    testWidgets(
      '$language answers are open and missing labels use translated field metadata',
      (tester) async {
        await open(
          tester,
          language: language,
          count: 0,
          extraFields: [
            {
              'id': 201,
              'type': 'city',
              'title': null,
              'is_ticket_field': false,
            },
            {
              'id': 202,
              'type': 'text',
              'title': 'null',
              'is_ticket_field': false,
            },
            {
              'id': 203,
              'type': 'text',
              'title': 'Custom question',
              'is_ticket_field': false,
            },
          ],
          answers: [
            {'201': 'Praha'},
            {'202': 'A saved answer'},
            {'203': 'Custom answer'},
          ],
        );
        expect(find.text('Praha'), findsOneWidget);
        expect(find.text('A saved answer'), findsOneWidget);
        expect(find.text('Custom question'), findsOneWidget);
        expect(find.text('null'), findsNothing);
        final answerTile = tester.widget<ExpansionTile>(
          find.byKey(const PageStorageKey(('order-answers', 42))),
        );
        expect(answerTile.initiallyExpanded, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ticket expansion exposes local selection and clear-all removes it without a route change',
    (tester) async {
      await open(tester, language: 'en', count: 2, tab: 'tickets');
      await tester.tap(find.text('T-100'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('ticket-selection-100')),
            )
            .properties
            .selected,
        isTrue,
      );
      expect(find.byIcon(Icons.confirmation_number_outlined), findsNWidgets(2));
      expect(find.text('Historical supper'), findsNWidgets(2));
      await tester.tap(find.text('Show all entries'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('ticket-selection-100')),
            )
            .properties
            .selected,
        isFalse,
      );
      expect(find.byIcon(Icons.confirmation_number_outlined), findsNWidgets(2));
      expect(find.text('T-101'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel order is visible for authorized editors and opens existing confirmation',
    (tester) async {
      await open(tester, language: 'en', writable: true, canCancel: true);
      final cancel = find.text('Cancel order');
      expect(cancel, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'After cancellation, the order can no longer be edited.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, CommonStrings.back));
      await tester.pumpAndSettle();
      expect(find.text('Cancel order'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'overview uses canonical tabs, exposes customer link and keeps hidden note below contact',
    (tester) async {
      await open(tester, language: 'en');
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(5));
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.text('Hidden note'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Hidden note')).dy,
        lessThan(tester.getTopLeft(find.text('Order contents')).dy),
      );
      expect(find.text('Cancel order'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel capability does not expose mutation to a read-only viewer',
    (tester) async {
      await open(tester, language: 'en', canCancel: true, writable: false);
      expect(find.text('Cancel order'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('order answers edit one field inline and retain failed drafts', (
    tester,
  ) async {
    final original = [
      {'201': 'Praha'},
      {'202': 'customer@example.com'},
      {'203': 'Lunch'},
    ];
    final detail = OrderAdminDetail({
      'order': {
        'id': 42,
        'order_symbol': 'ORD-42',
        'state': 'ordered',
        'form_id': 88,
      },
      'answers': original,
      'fields': [
        {'id': 201, 'type': 'city', 'is_ticket_field': false},
        {'id': 202, 'type': 'email', 'is_ticket_field': false},
        {'id': 203, 'type': 'product_type', 'is_ticket_field': false},
      ],
    });
    final previousContext = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: OccasionModel(
        id: 71,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
      ),
    );
    final controller =
        OrderDetailController(
            orderId: 42,
            occasionId: 71,
            read: (_, __) async => {'code': 200, 'data': detail.json},
          )
          ..detail = detail
          ..loading = false;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      RightsService.occasionLinkModelNotifier.value = previousContext;
    });
    final environment = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: jsonDecode(
        File('assets/translations/en.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    final writes = <Map<String, dynamic>>[];
    var reject = true;
    var allowed = true;
    await environment.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: OrderDetailAnswers(
            detail: detail,
            controller: controller,
            canEdit: () => allowed,
            onSave: (id, value, expected) async {
              if (reject) throw StateError('The answers have changed.');
              writes.add({'id': id, 'value': value, 'expected': expected});
            },
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Edit: City'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Brno');
    await tester.pump();
    expect(controller.dirty, isTrue);
    expect(find.text(CommonStrings.save), findsNothing);
    await expectLater(controller.saveDrafts(), throwsA(isA<StateError>()));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('The answers have changed.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Brno',
    );
    expect(controller.dirty, isTrue);
    allowed = false;
    await expectLater(controller.saveDrafts(), throwsA(isA<StateError>()));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(controller.dirty, isTrue);
    allowed = true;
    reject = false;
    await controller.saveDrafts();
    await tester.pumpAndSettle();
    expect(writes, [
      {'id': 201, 'value': 'Brno', 'expected': original},
    ]);
    expect(controller.dirty, isFalse);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Edit: City'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Discarded draft');
    expect(controller.dirty, isTrue);
    controller.discardDraft();
    await tester.pumpAndSettle();
    expect(controller.dirty, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'right-hand row pencil opens the shared email draft inline with global discard',
    (tester) async {
      await open(
        tester,
        language: 'en',
        writable: true,
        extraFields: [
          {
            'id': 202,
            'type': 'email',
            'title': 'Contact email',
            'is_ticket_field': false,
          },
        ],
        answers: [
          {'202': 'alex@example.com'},
        ],
      );
      final controller = tester
          .widget<OrderDetailView>(find.byType(OrderDetailView))
          .controller;
      final edit = find.byTooltip('Edit: Contact email');
      await tester.ensureVisible(edit);
      expect(
        tester.getCenter(edit).dy,
        greaterThan(tester.getCenter(find.text('Contact email')).dy),
      );
      expect(find.text('Edit email'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      expect(input, findsOneWidget);
      expect(
        tester.widget<TextField>(input).controller,
        same(controller.email),
      );
      await tester.enterText(input, 'draft@example.invalid');
      await tester.pump();
      expect(controller.dirtyDraftCount, 1);
      expect(controller.dirtyInlineDraftCount, 0);
      expect(find.text('Save changes'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(controller.email.text, 'alex@example.com');
      expect(controller.dirty, isFalse);
      expect(find.text('Save changes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Escape from a focused inline textbox requests guarded detail close without dropping its draft',
    (tester) async {
      var closes = 0;
      await open(
        tester,
        language: 'en',
        writable: true,
        extraFields: [
          {
            'id': 202,
            'type': 'text',
            'title': 'Company',
            'is_ticket_field': false,
          },
        ],
        answers: [
          {'202': 'Praha'},
        ],
        onClose: () => closes++,
      );
      final edit = find.byTooltip('Edit: Company');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Brno');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(closes, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Brno',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'one sticky action bar covers multiple inline drafts and globally discards them',
    (tester) async {
      await open(
        tester,
        language: 'en',
        writable: true,
        extraFields: [
          {
            'id': 301,
            'type': 'text',
            'title': 'Company',
            'is_ticket_field': false,
          },
          {
            'id': 302,
            'type': 'phone',
            'title': 'Telephone',
            'is_ticket_field': false,
          },
        ],
        answers: [
          {'301': 'Original company'},
          {'302': '12345'},
        ],
      );
      await tester.ensureVisible(find.byTooltip('Edit: Company'));
      await tester.tap(find.byTooltip('Edit: Company'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Draft company');
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Edit: Telephone'));
      await tester.tap(find.byTooltip('Edit: Telephone'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '98765');
      await tester.pump();
      expect(find.text(CommonStrings.saveChanges), findsOneWidget);
      expect(find.textContaining('Neuloženo'), findsNothing);
      expect(find.text(CommonStrings.save), findsNothing);
      final saveRect = tester.getRect(find.text(CommonStrings.saveChanges));
      expect(
        saveRect.top,
        greaterThan(tester.getRect(find.byType(TabBar)).top),
      );
      expect(saveRect.bottom, lessThan(600));
      await tester.tap(find.text(DataGridStrings.discardChanges));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Original company'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget);
      expect(find.text(CommonStrings.saveChanges), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

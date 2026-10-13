import 'dart:convert';
import 'dart:io';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/waitlist_order_detail.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:trina_grid/trina_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Localization.load(const Locale('cs'),
        translations: Translations(
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>,
        ));
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = null;
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  Future<void> open(WidgetTester tester,
      {required String lifecycle, String? displayName}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WaitlistOrderDetail(
      order: OrderModel(id: 5, orderSymbol: '9W6L1I6R4V', state: 'waitlisted'),
      loadDetail: (id) async {
        expect(id, 5);
        loads++;
        return {
          'occasionTitle': 'Festival & letní setkání',
          'tickets': [
            {
              'id': 8837,
              'displayName': displayName,
              'lifecycle': lifecycle,
              'ticket_symbol': null,
              'waitlist_queue_at': null,
              'created_at': null,
              'updated_at': null
            }
          ],
          'capacity': {'serverTime': null},
          'offers': [],
          'linkedOrders': [],
        };
      },
    ))));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Festival & letní setkání'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text(WaitlistStrings.offers), findsNothing);
    expect(find.text(WaitlistStrings.linkedOrders), findsNothing);
    expect(find.text(WaitlistStrings.withdraw), findsNothing);
    expect(find.text(WaitlistStrings.offerPlace), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('8837'), findsNothing);
    expect(find.textContaining('Osoba 1'), findsNothing);
  }

  testWidgets(
      'withdrawn single ticket shows safe display name and no empty sections or actions',
      (tester) async {
    await open(tester, lifecycle: 'withdrawn', displayName: 'Jana <Nováková>');
    expect(find.text('Jana <Nováková>'), findsOneWidget);
    expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('single readonly waiting ticket uses canonical application label',
      (tester) async {
    expect(RightsService.isEditorOrder(), isFalse);
    await open(tester, lifecycle: 'waiting');
    expect(find.text(OrdersStrings.itemSingular), findsOneWidget);
    expect(find.text(WaitlistStrings.text('waiting')), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });
  testWidgets(
      'withdraw command refreshes canonical detail and parent active grid',
      (tester) async {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}),
    );
    var lifecycle = 'waiting';
    var gridLabel = '1 Čeká';
    var changes = 0;
    final mutations = <Map<String, dynamic>>[];
    final order =
        OrderModel(id: 5, state: 'waitlisted', orderSymbol: 'REGISTRATION');
    late StateSetter parentState;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      parentState = setState;
      return Scaffold(
          body: Column(children: [
        Text(gridLabel, key: const Key('grid-summary')),
        Expanded(
            child: WaitlistOrderDetail(
          order: order,
          loadDetail: (_) async => {
            'tickets': [
              {'id': 8837, 'displayName': 'Jana', 'lifecycle': lifecycle}
            ],
            'offers': [],
            'linkedOrders': [],
            'waitlistSummary': {
              'counts': {lifecycle: 1},
              'isActive': lifecycle == 'waiting',
              'allowedActions': lifecycle == 'waiting'
                  ? ['view', 'withdraw', 'offer']
                  : ['view']
            },
          },
          executeCommand: (operation, payload) async {
            mutations.add({'operation': operation, ...payload});
            lifecycle = 'withdrawn';
            return {'status': 'applied', 'code': 200};
          },
          onChanged: () async {
            changes++;
            parentState(() => gridLabel = '1 Vyřazen');
          },
        )),
      ]));
    })));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(OutlinedButton, WaitlistStrings.withdraw));
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.withdrawTitle), findsOneWidget);
    expect(find.textContaining(WaitlistStrings.withdrawExplanation), findsOneWidget);
    expect(find.text(WaitlistStrings.title), findsNothing);
    expect(mutations, isEmpty);
    await tester
        .tap(find.widgetWithText(ElevatedButton, WaitlistStrings.withdraw));
    await tester.pumpAndSettle();
    expect(mutations, [
      {
        'operation': 'withdraw',
        'orderId': 5,
        'ticketIds': [8837]
      }
    ]);
    expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
    expect(changes, 1);
    expect(find.text('1 Čeká'), findsNothing);
    expect(find.text('1 Vyřazen'), findsOneWidget);
    expect(order.waitlistSummary!.counts, {'withdrawn': 1});
    expect(
        OrderGridFilters.orderIsActive(TrinaRow(cells: {
          EshopColumns.ORDER_MODEL_REFERENCE: TrinaCell(value: order)
        })),
        isFalse);
    expect(order.state, 'waitlisted',
        reason:
            'Client retains canonical order state and uses server activity');
  });

  Map<String, dynamic> waitingDetail({bool canSendOffers = true}) => {
        'tickets': [
          {'id': 8837, 'displayName': 'Jana', 'lifecycle': 'waiting'}
        ],
        'offers': [],
        'linkedOrders': [],
        'capacity': {'canSendOffers': canSendOffers},
      };
  void editor() =>
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}),
      );

  testWidgets(
      'cancelling withdrawal confirmation sends no mutation and keeps waiting',
      (tester) async {
    editor();
    var mutations = 0;
    var refreshed = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WaitlistOrderDetail(
      order: OrderModel(id: 5, state: 'waitlisted'),
      loadDetail: (_) async => waitingDetail(),
      executeCommand: (_, __) async {
        mutations++;
        return {};
      },
      onChanged: () async {
        refreshed++;
      },
    ))));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(OutlinedButton, WaitlistStrings.withdraw));
    await tester.pumpAndSettle();
    expect(find.textContaining(WaitlistStrings.withdrawExplanation), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pumpAndSettle();
    expect(mutations, 0);
    expect(refreshed, 0);
    expect(find.text(WaitlistStrings.text('waiting')), findsOneWidget);
  });

  testWidgets(
      'offer opens canonical preparation directly',
      (tester) async {
    editor();
    final form = FormModel(id: 7, waitlistEnabled: true);
    var opened = 0;
    var refreshed = 0;
    final order = OrderModel(id: 5, state: 'waitlisted', form: form);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WaitlistOrderDetail(
      order: order,
      loadDetail: (_) async => waitingDetail(),
      onChanged: () async {
        refreshed++;
      },
      offerDialogBuilder: (selectedForm, orders) {
        expect(identical(selectedForm, form), isTrue);
        expect(orders.single.id, 5);
        opened++;
        return Builder(
            builder: (context) => AlertDialog(
                  title: const Text('Canonical offer review'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close review'))
                  ],
                ));
      },
    ))));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(OutlinedButton, WaitlistStrings.offerPlace));
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.offerExplanation), findsNothing);
    expect(opened, 1);
    expect(find.text('Canonical offer review'), findsOneWidget);
    await tester.tap(find.text('Close review'));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets(
      'server capacity denial disables offer without changing withdrawal eligibility',
      (tester) async {
    editor();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WaitlistOrderDetail(
      order: OrderModel(
          id: 5,
          state: 'waitlisted',
          form: FormModel(id: 7, waitlistEnabled: true)),
      loadDetail: (_) async => waitingDetail(canSendOffers: false),
    ))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, WaitlistStrings.offerPlace))
            .onPressed,
        isNull);
    expect(find.text(WaitlistStrings.full), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, WaitlistStrings.withdraw))
            .onPressed,
        isNotNull);
  });

  testWidgets('successful withdrawal stays completed when parent refresh fails',
      (tester) async {
    editor();
    var lifecycle = 'waiting';
    var mutations = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WaitlistOrderDetail(
      order: OrderModel(id: 5, state: 'waitlisted'),
      loadDetail: (_) async => {
        ...waitingDetail(),
        'tickets': [
          {'id': 8837, 'lifecycle': lifecycle}
        ]
      },
      executeCommand: (_, __) async {
        mutations++;
        lifecycle = 'withdrawn';
        return {'code': 200};
      },
      onChanged: () async => throw StateError('read temporarily unavailable'),
    ))));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(OutlinedButton, WaitlistStrings.withdraw));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ElevatedButton, WaitlistStrings.withdraw));
    await tester.pumpAndSettle();
    expect(mutations, 1);
    expect(find.text(WaitlistStrings.text('withdrawn')), findsOneWidget);
    expect(find.text(WaitlistStrings.refreshAfterMutation), findsOneWidget);
    expect(find.text(WaitlistStrings.stale), findsNothing);
    expect(find.widgetWithText(OutlinedButton, WaitlistStrings.withdraw),
        findsNothing);
  });
  for (final count in [1, 2]) {
    testWidgets('offered $count selection enables only scoped offer actions', (tester) async {
      editor();
      zones.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Prague'));
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sent = <Map<String,dynamic>>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WaitlistOrderDetail(
        order: OrderModel(id: 5, state: 'waitlisted', form: FormModel(id: 7, waitlistEnabled: true)),
        loadDetail: (_) async => {
          'tickets': [for (var i=1;i<=count;i++) {'id':i,'displayName':'Junák $i','lifecycle':'offered'}],
          'offers': [{'id':'offer-one','expires_at':'2030-01-02T12:00:00Z','slots':[for(var i=1;i<=count;i++) {'ticketId':i,'outcome':'pending'}]}],
          'capacity': {'canSendOffers':false,'serverTime':'2030-01-01T12:00:00Z'},
        },
        executeCommand: (operation,payload) async {sent.add({'operation':operation,...payload}); return {'code':200};},
      ))));
      await tester.pumpAndSettle();
      expect(find.text(WaitlistStrings.full),findsNothing);
      expect(find.text(WaitlistStrings.offerPlace),findsNothing);
      expect(find.widgetWithText(FilledButton, WaitlistStrings.text('completeRegistration')),findsOneWidget);
      final decline=find.widgetWithText(TextButton,WaitlistStrings.text('recordDecline'));
      if(count==2) {
        expect(tester.widget<TextButton>(decline).onPressed,isNull);
        expect(find.text(WaitlistStrings.text('offerSelectionRequired')),findsOneWidget);
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
      } else {expect(find.byType(Checkbox),findsNothing);}
      expect(tester.widget<TextButton>(decline).onPressed,isNotNull);
      await tester.tap(decline);
      await tester.pumpAndSettle();
      expect(find.textContaining(WaitlistStrings.declineOfferExplanation),findsOneWidget);
      expect(sent,isEmpty);
      await tester.tap(find.widgetWithText(ElevatedButton,WaitlistStrings.text('recordDecline')));
      await tester.pumpAndSettle();
      expect(sent.single['ticketIds'],[1]);
      expect(sent.single['offerId'],'offer-one');
    });
  }

}

import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/waitlist_summary_model.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/waitlist_offers_dialog.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/data_services/rights_service.dart';
// The localization fixture uses its shared_preferences dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'package:trina_grid/trina_grid.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <Map<String, dynamic>>[];
  final proposalCalls = <int>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    zones.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  });
  Future<Map<String, dynamic>> proposal(int form) async {
    proposalCalls.add(form);
    return {
      'revision': 70 + form,
      'serverTime': '2026-10-13T12:00:00Z',
      'offerDurationSeconds': 3600,
      'capacity': {
        'enabled': true,
        'limit': 10,
        'canSendOffers': true,
        'offerablePlaces': 8
      },
      'recipients': form == 7
          ? [
              {'orderId': 5, 'count': 1},
              {'orderId': 6, 'count': 2}
            ]
          : [
              {'orderId': 8, 'count': 1},
              {'orderId': 9, 'count': 2}
            ]
    };
  }

  setUp(() {
    sent.clear();
    proposalCalls.clear();
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  OrderModel order(int id,
      {int form = 7,
      String state = 'waitlisted',
      String lifecycle = 'waiting',
      bool active = true}) {
    final result = OrderModel(
        id: id,
        formId: form,
        orderSymbol: 'ORDER$id',
        state: state,
        active: active);
    result.waitlistSummary = state == 'waitlisted'
        ? WaitlistSummaryModel.fromJson({
            'counts': {lifecycle: 1},
            'isActive': active,
            'allowedActions': ['view', 'offer', 'withdraw']
          })
        : null;
    result.paymentInfoModel = PaymentInfoModel();
    return result;
  }

  late SingleDataGridController<OrderModel> grid;
  var refreshed = 0;
  Future<void> open(WidgetTester tester, List<OrderModel> orders,
      {List<FormModel>? forms}) async {
    refreshed = 0;
    final configured =
        forms ?? [FormModel(id: 7, title: 'Form seven', waitlistEnabled: true)];
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(EasyLocalization(
        key: UniqueKey(),
        supportedLocales: const [Locale('cs')],
        path: 'unused',
        assetLoader: _Translations(),
        child: Builder(
            builder: (localized) => MaterialApp(
                locale: localized.locale,
                supportedLocales: localized.supportedLocales,
                localizationsDelegates: localized.localizationDelegates,
                home: Scaffold(body: Builder(builder: (context) {
                  final action = createWaitlistOffersAction(context,
                      forms: () => configured,
                      controller: () => grid,
                      offerDialogBuilder: (form, recipients, ids) =>
                          WaitlistOffersDialog(
                              form: form,
                              orders: recipients,
                              selectedOrderIds: ids,
                              loadProposal: proposal,
                              loadPreview: (_) async => {
                                    'template': {
                                      'subject': 'Offer {{order_symbol}}',
                                      'html': '<p>{{offered_count}}</p>'
                                    },
                                    'wrapper': {'html': '{{content}}'},
                                    'occasionTitle': 'Fixture'
                                  },
                              executeCommand: (operation, payload) async {
                                sent.add({
                                  'operation': operation,
                                  'payload': payload
                                });
                                return {'code': 200};
                              }),
                      onRefresh: () async {
                        refreshed++;
                      });
                  grid = SingleDataGridController<OrderModel>(
                      context: context,
                      loadData: () async => orders,
                      fromPlutoJson: OrderModel.fromPlutoJson,
                      firstColumnType: DataGridFirstColumn.check,
                      idColumn: EshopColumns.ORDER_ID,
                      additionalFilterEnabled: true,
                      additionalRowPredicate: OrderGridFilters.orderIsActive,
                      actionsExtended: DataGridActionsController(
                          isAddActionPossible: () => false,
                          areAllActionsEnabled: () => true),
                      headerChildren: [
                        if (RightsService.isEditorOrder() &&
                            hasActiveWaitlistOrders(orders))
                          action
                      ],
                      columns: [
                        TrinaColumn(
                            title: 'ID',
                            field: EshopColumns.ORDER_ID,
                            type: TrinaColumnType.number()),
                        TrinaColumn(
                            title: 'Symbol',
                            field: EshopColumns.ORDER_SYMBOL,
                            type: TrinaColumnType.text()),
                        TrinaColumn(
                            title: 'Note',
                            field: EshopColumns.ORDER_NOTE_HIDDEN,
                            type: TrinaColumnType.text())
                      ]);
                  return SingleTableDataGrid(grid);
                }))))));
    await tester.pumpAndSettle();
  }

  Finder toolbar() => find.widgetWithText(ElevatedButton, WaitlistStrings.send);
  Future<void> check(WidgetTester tester, int id) async {
    grid.stateManager.setRowChecked(
        grid.rows.singleWhere(
            (row) => row.cells[EshopColumns.ORDER_ID]!.value == id),
        true);
    grid.stateManager.notifyListeners();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'form configuration alone and fully withdrawn history do not expose offers toolbar',
      (tester) async {
    await open(tester, [order(11, state: 'sent')]);
    expect(toolbar(), findsNothing);
    await open(tester, [
      order(11, state: 'sent'),
      order(5, lifecycle: 'withdrawn', active: false)
    ]);
    expect(toolbar(), findsNothing);
    expect(grid.stateManager.rows, hasLength(1));
    expect(proposalCalls, isEmpty);
  });

  testWidgets(
      'none checked and ordinary-only selection stay disabled; selected waiting uses real send path',
      (tester) async {
    await open(tester, [order(5), order(6), order(11, state: 'sent')]);
    expect(toolbar(), findsOneWidget);
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNull);
    await check(tester, 11);
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNull);
    await check(tester, 5);
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNotNull);
    await tester.tap(toolbar());
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<WaitlistOffersDialog>(find.byType(WaitlistOffersDialog));
    expect(dialog.selectedOrderIds, {5});
    expect(dialog.orders.map((order) => order.id), [5]);
    expect(
        find.descendant(
            of: find.byType(WaitlistOffersDialog),
            matching: find.byType(TextField)),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
    expect(sent.single['payload']['formId'], 7);
    expect(sent.single['payload']['revision'], 77);
    expect(sent.single['payload']['recipients'], [
      {'orderId': 5, 'count': 1}
    ]);
    expect(find.byType(WaitlistOffersDialog), findsNothing);
    expect(refreshed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mixed waiting forms show only selected forms and chosen form sends only its checked recipients',
      (tester) async {
    await open(tester, [
      order(5),
      order(6),
      order(8, form: 8),
      order(9, form: 8)
    ], forms: [
      FormModel(id: 7, title: 'Form seven', waitlistEnabled: true),
      FormModel(id: 8, title: 'Form eight', waitlistEnabled: true),
      FormModel(id: 10, title: 'Unselected form', waitlistEnabled: true)
    ]);
    await check(tester, 5);
    await check(tester, 8);
    await tester.tap(toolbar());
    await tester.pumpAndSettle();
    expect(find.text('Form seven'), findsOneWidget);
    expect(find.text('Form eight'), findsOneWidget);
    expect(find.text('Unselected form'), findsNothing);
    await tester.tap(find.text('Form eight'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<WaitlistOffersDialog>(find.byType(WaitlistOffersDialog))
            .selectedOrderIds,
        {8});
    expect(proposalCalls, [8]);
    await tester.tap(find.widgetWithText(FilledButton, WaitlistStrings.send));
    await tester.pumpAndSettle();
    expect(sent.single['payload']['recipients'], [
      {'orderId': 8, 'count': 1}
    ]);
    expect(sent.single['payload']['formId'], 8);
  });

  testWidgets(
      'active offered rows stay visible but ineligible; readonly role has no toolbar',
      (tester) async {
    await open(tester, [order(5, lifecycle: 'offered')]);
    expect(toolbar(), findsOneWidget);
    await check(tester, 5);
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNull);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser:
            OccasionUserModel.fromJson({'is_editor_order_view': true}));
    await open(tester, [order(5)]);
    expect(toolbar(), findsNothing);
  });

  testWidgets('offer action keeps unsaved row drafts protected',
      (tester) async {
    await open(tester, [order(5)]);
    await check(tester, 5);
    final row = grid.rows.single;
    row.cells[EshopColumns.ORDER_NOTE_HIDDEN]!.value = 'unsaved draft';
    row.setState(TrinaRowState.updated);
    grid.updatedRows.add(row);
    grid.stateManager.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNull);
    expect(row.cells[EshopColumns.ORDER_NOTE_HIDDEN]!.value, 'unsaved draft');
    expect(grid.updatedRows, contains(row));
    expect(proposalCalls, isEmpty);
  });
}

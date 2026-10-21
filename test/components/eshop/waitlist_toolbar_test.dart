import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'dart:convert';

import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/waitlist_summary_model.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart';
import 'package:festapp_core/forms.dart';
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
              {'orderId': 5, 'count': 1, 'waitingCount': 1},
              {'orderId': 6, 'count': 2, 'waitingCount': 2}
            ]
          : [
              {'orderId': 8, 'count': 1, 'waitingCount': 1},
              {'orderId': 9, 'count': 2, 'waitingCount': 2}
            ]
    };
  }

  setUp(() {
    sent.clear();
    proposalCalls.clear();
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.ordersWrite: true},
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
            'counts': {lifecycle: id == 6 || id == 9 ? 2 : 1},
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
      {List<FormBundle>? forms}) async {
    refreshed = 0;
    var configured = forms ??
        [
          FormBundle(
              definition: FormDefinition(
                  id: 7, title: 'Form seven', waitlistEnabled: true))
        ];
    configured = configured
        .map((form) => form.withDefinition(form.definition.copyWith(
              capacity: form.definition.capacity ??
                  FormCapacityModel.fromJson(
                      {'canSendOffers': true, 'offerablePlaces': 8}),
            )))
        .toList();
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
                  Widget offerButton(BuildContext context,
                          SingleDataGridController<OrderModel> grid) =>
                      waitlistOffersToolbarButton(context, grid,
                          forms: configured,
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
                      idColumn: EshopColumnIds.ORDER_ID,
                      additionalFilterEnabled: true,
                      additionalRowPredicate: OrderGridFilters.orderIsActive,
                      actionsExtended: DataGridActionsController(
                          isAddActionPossible: () => false,
                          areAllActionsEnabled: () => true),
                      headerFilterBuilder: (context, grid) =>
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            OrderGridFilters.filterButton(context, grid,
                                label: WaitlistStrings.text('active')),
                            offerButton(context, grid),
                          ]),
                      columns: [
                        TrinaColumn(
                            title: 'ID',
                            field: EshopColumnIds.ORDER_ID,
                            type: TrinaColumnType.number()),
                        TrinaColumn(
                            title: 'Symbol',
                            field: EshopColumnIds.ORDER_SYMBOL,
                            type: TrinaColumnType.text()),
                        TrinaColumn(
                            title: 'Note',
                            field: EshopColumnIds.ORDER_NOTE_HIDDEN,
                            type: TrinaColumnType.text())
                      ]);
                  return SingleTableDataGrid(grid);
                }))))));
    await tester.pumpAndSettle();
  }

  Finder toolbar() => find.ancestor(
      of: find.byWidgetPredicate((widget) =>
          widget is Text &&
          widget.data?.startsWith('${WaitlistStrings.send} (') == true),
      matching: find.byType(ElevatedButton));
  Future<void> check(WidgetTester tester, int id) async {
    final target = grid.rows
        .singleWhere((row) => row.cells[EshopColumnIds.ORDER_ID]!.value == id);
    if (!grid.stateManager.rows.contains(target)) {
      grid.toggleAdditionalFilter(false);
    }
    grid.stateManager.setRowChecked(
        grid.rows.singleWhere(
            (row) => row.cells[EshopColumnIds.ORDER_ID]!.value == id),
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
      'offers work without selection and checked waiting uses the real send path',
      (tester) async {
    await open(tester, [order(5), order(6), order(11, state: 'sent')]);
    expect(toolbar(), findsOneWidget);
    expect(find.text('${WaitlistStrings.send} (3)'), findsOneWidget);
    expect(grid.stateManager.rows, hasLength(3));
    final active = find.byKey(const ValueKey('onlyNonCancelled'));
    expect(tester.getTopLeft(toolbar()).dx,
        greaterThan(tester.getTopLeft(active).dx));
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNotNull);
    await check(tester, 11);
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNotNull);
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
        findsNothing);
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
      FormBundle(
          definition: FormDefinition(
              id: 7, title: 'Form seven', waitlistEnabled: true)),
      FormBundle(
          definition: FormDefinition(
              id: 8, title: 'Form eight', waitlistEnabled: true)),
      FormBundle(
          definition: FormDefinition(
              id: 10, title: 'Unselected form', waitlistEnabled: true))
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
    expect(toolbar(), findsNothing);
    await check(tester, 5);
    expect(toolbar(), findsNothing);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.ordersRead: true},
        occasionUser:
            OccasionUserModel.fromJson({'is_editor_order_view': true}));
    await open(tester, [order(5)]);
    expect(toolbar(), findsNothing);
  });

  testWidgets(
      'zero offerable capacity hides toolbar even with waiting registrations',
      (tester) async {
    await open(tester, [
      order(5)
    ], forms: [
      FormBundle(
          definition: FormDefinition(
              id: 7,
              waitlistEnabled: true,
              capacity: FormCapacityModel.fromJson(
                  {'canSendOffers': false, 'offerablePlaces': 0})))
    ]);
    expect(toolbar(), findsNothing);
  });

  testWidgets('unselected active waiting registrations open offer preparation',
      (tester) async {
    await open(tester, [order(5), order(11, state: 'sent')]);
    expect(grid.stateManager.rows, hasLength(2));
    await tester.tap(toolbar());
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<WaitlistOffersDialog>(find.byType(WaitlistOffersDialog));
    expect(dialog.orders.map((order) => order.id), [5]);
    expect(dialog.selectedOrderIds, {5});
    expect(tester.takeException(), isNull);
  });

  testWidgets('offer action keeps unsaved row drafts protected',
      (tester) async {
    await open(tester, [order(5)]);
    await check(tester, 5);
    final row = grid.rows.single;
    row.cells[EshopColumnIds.ORDER_NOTE_HIDDEN]!.value = 'unsaved draft';
    row.setState(TrinaRowState.updated);
    grid.updatedRows.add(row);
    grid.stateManager.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(toolbar()).onPressed, isNull);
    expect(row.cells[EshopColumnIds.ORDER_NOTE_HIDDEN]!.value, 'unsaved draft');
    expect(grid.updatedRows, contains(row));
    expect(proposalCalls, isEmpty);
  });
}

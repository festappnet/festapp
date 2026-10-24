import 'dart:ui' show PointerDeviceKind;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only locale delegates from the existing easy_localization SDK dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/eshop/views/ticket_batches_page.dart';
import 'package:fstapp/components/eshop/views/ticket_batch_table.dart';
import 'package:fstapp/components/eshop/views/ticket_batch_items_table.dart';
import 'package:fstapp/theme_config.dart';
import 'package:trina_grid/trina_grid.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  test('pregeneration requires an enabled ticket feature and explicit opt-in',
      () {
    for (final config in [
      <String, dynamic>{'code': 'ticket', 'is_enabled': true},
      <String, dynamic>{
        'code': 'ticket',
        'is_enabled': true,
        'pregenerated_tickets': false
      },
      <String, dynamic>{
        'code': 'ticket',
        'is_enabled': false,
        'pregenerated_tickets': true
      },
    ]) {
      expect(
          FeatureService.isTicketPregenerationEnabled(
              features: [Feature.fromJson(config)]),
          isFalse);
    }
    expect(FeatureService.isTicketPregenerationEnabled(features: []), isFalse);
    final enabled = Feature.fromJson({
      'code': 'ticket',
      'is_enabled': true,
      'pregenerated_tickets': true
    }) as TicketFeature;
    expect(
        FeatureService.isTicketPregenerationEnabled(
            features: [Feature.fromJson(enabled.toJson())]),
        isTrue);
    expect(TicketFeature(code: FeatureConstants.ticket).pregeneratedTickets,
        isFalse);
  });

  testWidgets('disabled direct batch route does not initialize the backend',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TicketBatchesPage()));
    expect(tester.takeException(), isNull);
    expect(find.byType(TicketBatchListPage), findsNothing);
  });

  Map<String, dynamic> form(int id, String title) => {
        'id': id,
        'title': title,
        'products': [
          {'id': id * 10, 'title': 'Vstupenka', 'price': 250, 'currency': 'CZK'}
        ]
      };
  Future<void> mountDialog(WidgetTester tester, List<Map> options) async {
    await environment.pumpWidget(
        tester,
        MaterialApp(
            theme: ThemeConfig.theme(),
            home: Scaffold(body: TicketBatchCreateDialog(options: options))));
    await tester.pumpAndSettle();
  }

  FilledButton preview(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  for (final width in [390.0, 1100.0]) {
    testWidgets(
        'single form is hidden and selected; quantity validated at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountDialog(tester, [form(1, 'Hlavní formulář')]);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(find.text('Formulář'), findsNothing);
      expect(preview(tester).onPressed, isNull);
      await tester.enterText(
          find.byType(TextField).first, 'Pokladna - večerní prodej');
      await tester.pump();
      expect(preview(tester).onPressed, isNotNull);
      for (final quantity in ['0', '201', 'abc']) {
        await tester.enterText(find.byType(TextField).last, quantity);
        await tester.pump();
        expect(preview(tester).onPressed, isNull);
      }
      await tester.enterText(find.byType(TextField).last, '200');
      await tester.pump();
      expect(preview(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'multiple forms keep selection; a form change selects its sole product',
      (tester) async {
    await mountDialog(
        tester, [form(1, 'První formulář'), form(2, 'Druhý formulář')]);
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).first, 'Pokladna');
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Druhý formulář').last);
    await tester.pumpAndSettle();
    expect(preview(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'table preserves counts, numeric sorting and opens the selected batch',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            locale: const Locale('cs'),
            supportedLocales: const [Locale('cs')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeConfig.theme(),
            home: Scaffold(
                body: TicketBatchTable(rows: const [
              {
                'id': 'batch-1',
                'title': 'Pokladna',
                'counts': {
                  'available': 10,
                  'soldActive': 2,
                  'voidedUnsold': 1,
                  'cancelledAfterSale': 1
                },
                'stockValue': 2500.5,
                'receivedAmount': 500,
                'currency': 'CZK'
              }
            ], onOpen: (id) => opened = id))));
    await tester.pumpAndSettle();
    final grid = tester.widget<TrinaGrid>(find.byType(TrinaGrid));
    expect(grid.rows.single.cells['voided']!.value, 2);
    expect(grid.columns.firstWhere((c) => c.field == 'available').type.isNumber,
        isTrue);
    expect(find.text('2\u00a0500,50'), findsOneWidget);
    final manager = tester.state<TrinaGridState>(find.byType(TrinaGrid)).stateManager;
    manager.setCurrentCell(grid.rows.single.cells['available'], 0);
    manager.setKeepFocus(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'), kind: PointerDeviceKind.mouse);
    expect(opened, 'batch-1');
    opened = null;
    await tester.tap(find.widgetWithText(TextButton, 'Detail a tisk'));
    expect(opened, 'batch-1');
    opened = null;
    await tester.tap(find.text('Pokladna'));
    expect(opened, 'batch-1');
    opened = null;
    await tester.tap(find.text('10'));
    expect(opened, 'batch-1');
    opened = null;
    manager.setKeepFocus(false);
    await tester.pumpAndSettle();
    final cell = find.ancestor(of: find.text('10'), matching: find.byType(InkWell)).first;
    final area = tester.getRect(cell);
    await tester.tapAt(Offset(area.left + 2, area.center.dy), kind: PointerDeviceKind.mouse);
    expect(opened, 'batch-1');
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('ticket grid selection, QR updates and busy state at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = [
        {
          'id': 1,
          'ordinal': 1,
          'ticket_symbol': 'QR-1',
          'state': 'ordered',
          'sale_order_id': null
        },
        {
          'id': 2,
          'ordinal': 2,
          'ticket_symbol': 'QR-2',
          'state': 'ordered',
          'sale_order_id': null
        },
        {
          'id': 3,
          'ordinal': 3,
          'ticket_symbol': 'QR-3',
          'state': 'paid',
          'sale_order_id': 50
        },
        {
          'id': 4,
          'ordinal': 4,
          'ticket_symbol': 'QR-4',
          'state': 'storno',
          'sale_order_id': null
        },
      ];
      var selected = <int>{};
      var enabled = true;
      late StateSetter update;
      await environment.pumpWidget(
          tester,
          MaterialApp(
              locale: const Locale('cs'),
              supportedLocales: const [Locale('cs')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeConfig.theme(),
              home:
                  Scaffold(body: StatefulBuilder(builder: (context, setState) {
                update = setState;
                return TicketBatchItemsTable(
                    items: items,
                    selected: selected,
                    enabled: enabled,
                    onSelectionChanged: (ids) =>
                        setState(() => selected = ids));
              }))));
      await tester.pumpAndSettle();
      final manager =
          tester.state<TrinaGridState>(find.byType(TrinaGrid)).stateManager;
      // The native select-all checkbox must exclude sold and void tickets.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(selected, {1, 2});
      expect(
          manager.refRows.originalList
              .where((row) => row.checked == true)
              .length,
          2);
      final column = manager.columns.first;
      expect(column.disableRowCheckboxWhen!(manager.rows[2]), isTrue);
      expect(column.disableRowCheckboxWhen!(manager.rows[3]), isTrue);
      manager.sortDescending(column);
      update(() => selected = {2}); // Same update as selecting a scanned QR.
      await tester.pumpAndSettle();
      expect(tester.state<TrinaGridState>(find.byType(TrinaGrid)).stateManager,
          same(manager));
      expect(manager.rows.first.cells['ordinal']!.value, 4);
      expect(
          manager.refRows.originalList
              .where((row) => row.checked == true)
              .single
              .cells['id']!
              .value,
          2);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(column.disableRowCheckboxWhen!(manager.refRows.originalList.first),
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

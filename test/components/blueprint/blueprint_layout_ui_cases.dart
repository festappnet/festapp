import 'package:fstapp/components/eshop/seat_order_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import '../../support/fixtures/blueprint_order_preview_fixture.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../support/fixtures/blueprint_swap_preview_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_feedback.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';
import 'package:fstapp/components/blueprint/views/blueprint_standing_setup_dialog.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_inline_name.dart';
import '../../support/fixtures/blueprint_native_font_fixture.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/components/blueprint/seat_reservation/widgets/seat_reservation_widget.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_controller.dart';
import 'package:fstapp/components/blueprint/views/blueprint_standing_capacity_control.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/eshop/ticket_cancellation_updates.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fstapp/components/blueprint/blueprint_text_preparation.dart';
import '../../support/fixtures/blueprint_font_registry_fixture.dart';
import 'package:fstapp/components/blueprint/views/blueprint_plan_editor.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'dart:ui' show SemanticsAction;
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_demo.dart';
import 'dart:async';
import '../../support/fixtures/root_supabase_fixture.dart';
import 'package:flutter/services.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../support/fixtures/layout_canvas_fixture.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_host.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/eshop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';
import 'package:fstapp/components/fonts/ticket_font_catalog.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_resources.dart';
import 'package:fstapp/components/blueprint/views/blueprint_create_order_dialog.dart';
import 'package:fstapp/components/blueprint/views/blueprint_product_dialogs.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

late WidgetEnvironmentFixture environment;
FutureOr<http.Response> Function(http.Request)? pickerResponse;
const pickerNode = '10000000-0000-4000-8000-000000000011';
Map<String, dynamic> pickerPayload(String state, {DateTime? expiry}) => {
      ...BlueprintLayoutSnapshot(
          blueprintId: 4,
          occasionId: 8,
          title: 'Hall',
          revision: 1,
          document: VenueLayoutDocument(nodes: [
            LayoutNode(
                id: pickerNode, kind: 'seat', x: 100, y: 100, label: 'A1')
          ]),
          seatBindings: {
            pickerNode: const BlueprintSeatBinding(
                nodeId: pickerNode, spotId: 11, productId: 1, title: 'A1')
          }).toJson(),
      'layoutResources': blueprintPreparedResourcesFixture(
          VenueLayoutDocument(nodes: [
        LayoutNode(id: pickerNode, kind: 'seat', x: 100, y: 100, label: 'A1')
      ])),
      'expiresAt': expiry?.toIso8601String(),
      'spots': [
        {'id': 11, 'title': 'A1', 'product': 1, 'state': state}
      ],
      'products': [
        {'id': 1, 'title': 'Standard', 'price': 100, 'is_available': true}
      ],
    };
http.Response pickerRead(http.Request request, String state,
        {DateTime? expiry}) =>
    http.Response(
        jsonEncode({'code': 200, 'data': pickerPayload(state, expiry: expiry)}),
        200,
        headers: {'content-type': 'application/json'},
        request: request);

void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  late LocalAppStorageFixture commandStorage;
  setUpAll(() async {
    commandStorage = await LocalAppStorageFixture.open();
    backend = await RootSupabaseFixture.open((request) =>
        pickerResponse?.call(request) ??
        (throw StateError('Unexpected UI fixture request')));
    // Resolve asset I/O before widget fake-async zones can cache a pending read.
    await TicketFontCatalog.loadFamilies();
  });
  tearDownAll(() async {
    await backend.dispose();
    await commandStorage.dispose();
  });
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  tearDown(() {
    pickerResponse = null;
  });
  testWidgetsWithEnvironment(() => environment,
      'commercial name edits inline, trims once and cancels with Escape',
      (tester) async {
    final changes = <String>[];
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: BlueprintInlineName(
                    nodeId: 'table',
                    name: 'B3',
                    enabled: true,
                    onSubmitted: changes.add))));
    final edit = find.byKey(const ValueKey('rename-commercial-table'));
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(find.byType(TextField), ' B4 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['B4']);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cancelled');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(changes, ['B4']);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['B4']);
  });
  for (final mobile in [(390.0, 844.0, 1.0), (320.0, 640.0, 1.6)]) {
    testWidgetsWithEnvironment(() => environment,
        'mobile blueprint keeps canvas dominant and all actions reachable ${mobile.$1}',
        (tester) async {
      tester.view.physicalSize = Size(mobile.$1, mobile.$2);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rights = RightsService.occasionLinkModelNotifier.value;
      RightsService.occasionLinkModelNotifier.value =
          OccasionLinkModel(capabilities: {
        AuthorizationCapabilities.occasionsWrite: true,
        AuthorizationCapabilities.ordersWrite: true
      }, isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
      final tables = [
        for (var i = 0; i < 8; i++)
          tableLayout(
              shape: 'rect',
              count: 8,
              width: 200,
              height: 80,
              x: i.isEven ? 180 : 820,
              y: 220 + (i ~/ 2) * 420)
      ];
      final document = VenueLayoutDocument(canvas: {
        ...VenueLayoutDocument.empty().canvas,
        'width': 1000,
        'height': 1800
      }, nodes: [
        for (final table in tables) ...table.nodes
      ], attachments: [
        for (final table in tables) ...table.attachments
      ]);
      final seats = document.nodes.where((n) => n.kind == 'seat').toList();
      final source = BlueprintModel(
          layoutSnapshot: BlueprintLayoutSnapshot(
              blueprintId: 1,
              occasionId: 1,
              title: 'Mobile',
              revision: 1,
              document: document,
              seatBindings: {
                for (var i = 0; i < seats.length; i++)
                  seats[i].id: BlueprintSeatBinding(
                      nodeId: seats[i].id,
                      spotId: i + 1,
                      title: 'A${i + 1}',
                      productId: 1,
                      groupNodeId: seats[i].parentId)
              },
              groupProducts: {
                for (final table in tables) table.nodes.first.id: 1
              }),
          products: [
            ProductModel(
                id: 1,
                title: 'Místo',
                price: 200,
                productTypeString: ProductModel.spotType)
          ],
          spots: [
            for (var i = 0; i < seats.length; i++)
              BlueprintObjectModel(id: i + 1, state: 'available')
          ]);
      source.layoutResources = blueprintPreparedResourcesFixture(document);
      await environment.pumpWidget(
          tester,
          MaterialApp(
              locale: const Locale('cs'),
              supportedLocales: VenueLayoutLocalizations.supportedLocales,
              localizationsDelegates:
                  VenueLayoutLocalizations.localizationsDelegates,
              theme: ThemeConfig.theme(brightness: Brightness.dark),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(mobile.$3)),
                  child: child!),
              home: BlueprintLayoutHost(
                  source: source, reload: () async => source)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final toolbar = find.byKey(const ValueKey('layout-editor-toolbar'));
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(112));
      expect(
          tester.getSize(layoutCanvas()).height, greaterThan(mobile.$2 * .6));
      expect(find.byKey(const ValueKey('blueprint-start-order')).hitTestable(),
          findsOneWidget);
      expect(find.byKey(const ValueKey('layout-mobile-fit-plan')).hitTestable(),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('blueprint-more-actions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('blueprint-start-swap')).hitTestable(),
          findsOneWidget);
      expect(find.byKey(const ValueKey('blueprint-toggle-blocked')),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('blueprint-screen-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
              .interactionEnabled,
          isTrue);
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(112));
      expect(
          tester.getSize(layoutCanvas()).height, greaterThan(mobile.$2 * .6));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgetsWithEnvironment(() => environment,
      'public picker reconciles lost hold response before enabling Continue',
      (tester) async {
    var reads = 0;
    var holds = 0;
    final response = Completer<http.Response>();
    final selections = <List<BlueprintSeat>>[];
    final busy = <bool>[];
    pickerResponse = (request) {
      if (request.url.path.endsWith('select_spot')) {
        holds++;
        return response.future;
      }
      reads++;
      return pickerRead(request, reads == 1 ? 'available' : 'selected_by_me');
    };
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SeatReservationWidget(
                    blueprintId: 4,
                    secret: 'buyer',
                    formDataKey: 'form',
                    selectedSeats: const [],
                    onSelectionChanged: selections.add,
                    onPendingChanged: busy.add))));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<VenueLayoutPicker>(find.byType(VenueLayoutPicker));
    LayoutSelectionResult? outcome;
    picker.onSelectionRequested(
        {pickerNode}, true).then((value) => outcome = value);
    await tester.pump();
    expect(busy.last, isTrue);
    expect(find.text(CommonStrings.loading), findsOneWidget);
    response.completeError(StateError('lost response after commit'));
    for (var attempt = 0; attempt < 10 && outcome == null; attempt++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(outcome, isNotNull);
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(holds, 1);
    expect(selections.last.map((seat) => seat.seatId), [11]);
    expect(busy.last, isFalse);
    expect(
        tester
            .widget<VenueLayoutPicker>(find.byType(VenueLayoutPicker))
            .seatPresentation[pickerNode]!['selected'],
        isTrue);
  });
  testWidgetsWithEnvironment(() => environment,
      'public picker expiry refresh removes expired seats from form payload',
      (tester) async {
    var reads = 0;
    final selections = <List<BlueprintSeat>>[];
    final expiry = DateTime.now().add(const Duration(seconds: 2));
    pickerResponse = (request) => ++reads == 1
        ? pickerRead(request, 'selected_by_me', expiry: expiry)
        : pickerRead(request, 'ordered');
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SeatReservationWidget(
                    blueprintId: 4,
                    secret: 'buyer',
                    formDataKey: 'form',
                    selectedSeats: const [],
                    onSelectionChanged: selections.add))));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
    expect(selections.last.map((seat) => seat.seatId), [11]);
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(selections.last, isEmpty);
    final seat = tester
        .widget<VenueLayoutPicker>(find.byType(VenueLayoutPicker))
        .seatPresentation[pickerNode]!;
    expect(seat['selected'], isFalse);
    expect(seat['selectable'], isFalse);
    expect(seat['status'], 'occupied');
  });
  testWidgetsWithEnvironment(() => environment,
      'standing capacity field commits and focused undo restores live capacity',
      (tester) async {
    final id = newLayoutId();
    final c = BlueprintLayoutController(
        source: BlueprintModel(
            layoutSnapshot: BlueprintLayoutSnapshot(
                blueprintId: 4,
                occasionId: 8,
                title: 'Hall',
                revision: 2,
                document: VenueLayoutDocument(nodes: [
                  LayoutNode(
                      id: id,
                      kind: 'capacityArea',
                      x: 400,
                      y: 300,
                      width: 200,
                      height: 100,
                      properties: {'capacity': 0})
                ]),
                seatBindings: {},
                groupProducts: {},
                areaBindings: {
                  id: BlueprintAreaBinding(
                      nodeId: id, inventoryContextId: 3, productId: 9)
                }),
            areaAvailability: {
          id: {'capacity': 30, 'available': 12}
        },
            products: [
          ProductModel(id: 9, title: 'Standing', price: 80)
        ]));
    addTearDown(c.dispose);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: AnimatedBuilder(
                    animation: c,
                    builder: (_, __) => BlueprintStandingCapacityControl(
                        controller: c, nodeId: id, enabled: true)))));
    final field = find.byKey(const ValueKey('standing-capacity-field'));
    expect(tester.widget<TextField>(field).controller!.text, '30');
    expect(tester.widget<TextField>(field).decoration!.labelText,
        BlueprintStrings.standingCapacity);
    expect(tester.widget<TextField>(field).decoration!.helperText,
        BlueprintStrings.capacitySaveHint);
    await tester.enterText(field, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.areaCapacity(id), 25);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(c.areaCapacity(id), 30);
    expect(tester.widget<TextField>(field).controller!.text, '30');
  });
  testWidgetsWithEnvironment(() => environment,
      'admin order uses active form required customer and ticket fields without loaders',
      (tester) async {
    Map<String, dynamic>? submitted;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: BlueprintCreateOrderDialog(
          request: seatOrderRequestFixture(),
          commands: seatOrderCommandsFixture(
              fields: [
                {
                  'id': 601,
                  'type': 'name',
                  'title': 'Jméno zákazníka',
                  'is_required': true,
                  'is_hidden': false,
                  'is_ticket_field': false
                },
                {
                  'id': 602,
                  'type': 'text',
                  'title': 'Jméno návštěvníka',
                  'is_required': true,
                  'is_hidden': false,
                  'is_ticket_field': true
                },
              ],
              onQuote: (data) async {
                submitted = data;
                throw StateError('test_stop');
              }),
        ))));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'local@example.test');
    final confirm = find.widgetWithText(
        ElevatedButton, 'FeatureBlueprint.orderReview'.tr());
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    final customer =
        find.byWidgetPredicate((w) => w is FormBuilderField && w.name == '601');
    final attendee =
        find.byWidgetPredicate((w) => w is FormBuilderField && w.name == '602');
    await tester.ensureVisible(customer);
    await tester.enterText(customer, 'Jana');
    await tester.ensureVisible(attendee);
    await tester.enterText(attendee, 'Eva');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(submitted!['fields'], [
      {'601': 'Jana'}
    ]);
    expect(submitted!['ticket_fields'], {
      '71': [
        {'602': 'Eva', 'text': 'Eva'}
      ]
    });
    expect(submitted!['form_key'], '00000000-0000-4000-8000-000000000001');
  });
  testWidgetsWithEnvironment(() => environment,
      'seat order shows printed-batch rejection without exposing a confirmation or writing',
      (tester) async {
    var writes = 0;
    final commands = SupabaseSeatOrderCommands.withTransport(
        ClientCommandTransport((_, __) async {
      writes++;
      return null;
    }),
        readRpc: (_, params) async => params['p_input'] == null
            ? seatOrderRequirementsJson()
            : {'code': 409, 'reason': 'BATCH_TICKET_PRINT_IMMUTABLE'});
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: BlueprintCreateOrderDialog(
                    request: seatOrderRequestFixture(), commands: commands))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'local@example.invalid');
    await tester.tap(find.widgetWithText(
        ElevatedButton, 'FeatureBlueprint.orderReview'.tr()));
    await tester.pumpAndSettle();
    expect(
        find.text('FeatureBlueprint.orderBatchImmutable'.tr()), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, BlueprintStrings.confirmOrder),
        findsNothing);
    expect(writes, 0);
  });
  testWidgetsWithEnvironment(() => environment,
      'whole order cancellation email is an optional follow-up',
      (tester) async {
    await environment.pumpWidget(
        tester, const MaterialApp(home: Scaffold(body: Text('Ready'))));
    final context = tester.element(find.text('Ready'));
    final skipped =
        confirmCancelledOrderEmail(context, 'customer@example.test');
    await tester.pumpAndSettle();
    expect(find.textContaining('customer@example.test'), findsOneWidget);
    await tester.tap(find.text('Teď neposílat'));
    await tester.pumpAndSettle();
    expect(await skipped, isFalse);
    final accepted =
        confirmCancelledOrderEmail(context, 'customer@example.test');
    await tester.pumpAndSettle();
    await tester.tap(find.text(OrdersStrings.sendEmailButton));
    await tester.pumpAndSettle();
    expect(await accepted, isTrue);
  });
  testWidgetsWithEnvironment(() => environment,
      'local font can become the plan default through the shared picker',
      (tester) async {
    await tester.runAsync(TicketFontCatalog.loadFamilies);
    final registry = blueprintFontRegistryFixture();
    final roboto =
        registry.entries.firstWhere((e) => e.value['family'] == 'Roboto').key;
    final futura = registry.entries
        .firstWhere((e) => e.value['family'] == 'Futura PT')
        .key;
    final text = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        x: 200,
        y: 200,
        width: 200,
        height: 60,
        properties: const {
          'text': 'Font'
        },
        style: {
          'label': {'fontFamilyId': futura}
        });
    final document = VenueLayoutDocument(styles: {
      'label': {'fontFamilyId': futura}
    }, nodes: [
      text
    ]);
    final controller = VenueLayoutController(document,
        resources: blueprintPreparedResourcesFixture(document))
      ..select({text.id});
    addTearDown(controller.dispose);
    final provider = await tester.runAsync(() =>
        BlueprintTextResources.forSetupDraft('font-default-test',
            // Preview loads real local faces even when no shaping is needed.
            service: TicketLayoutService(
                transport: blueprintNativeFontReplyFixture)));
    // Complete engine registration outside fake async before preview widgets
    // can share a pending face with later tests through the font cache.
    await tester.runAsync(() async {
      for (final familyId in [futura, roboto]) {
        final faces = registry[familyId]!['faces'] as Map;
        await provider!.loadFace(faces['400:normal'] as String);
      }
    });
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintPlanEditor(
                controller: controller,
                loadTextResources: () async => provider!)));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('set-default-plan-font'));
    expect(action, findsNothing);
    final picker =
        tester.widget<FontFamilyPicker>(find.byType(FontFamilyPicker));
    await picker.onPreview!('Roboto');
    await tester.pumpAndSettle();
    expect(controller.document.nodes.single.style['label']['fontFamilyId'],
        roboto);
    expect(controller.canUndo, isFalse);
    picker.onPreviewEnd!();
    await tester.pumpAndSettle();
    expect(controller.document.nodes.single.style['label']['fontFamilyId'],
        futura);
    expect(controller.canUndo, isFalse);
    await picker.onSelected('Roboto');
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(controller.document.styles['label']['fontFamilyId'], roboto);
    expect(controller.document.nodes.single.style['label']['fontFamilyId'],
        roboto);
    expect(action, findsNothing);
    controller.undo();
    expect(controller.document.styles['label']['fontFamilyId'], futura);
    controller.undo();
    expect(controller.document.nodes.single.style['label']['fontFamilyId'],
        futura);
    expect(action, findsNothing);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'reservation workspace groups selected seats, highlights parent tables and confirms cancellation',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.occasionsWrite: true,
          AuthorizationCapabilities.ordersWrite: true
        },
        isAdmin: true,
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final tables = [
      for (var i = 0; i < 3; i++)
        LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            label: 'Desk ${i + 1}',
            x: 300.0 + i * 400,
            y: 300,
            surface: {'type': 'rect'})
    ];
    final seats = [
      for (var i = 0; i < 3; i++)
        LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            parentId: tables[i].id,
            x: 0,
            y: 100)
    ];
    final document = VenueLayoutDocument(nodes: [...tables, ...seats]);
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Workspace',
            revision: 1,
            document: document,
            seatBindings: {
              for (var i = 0; i < 3; i++)
                seats[i].id: BlueprintSeatBinding(
                    nodeId: seats[i].id,
                    spotId: 11 + i,
                    title: 'Seat ${i + 1}',
                    productId: 1,
                    groupNodeId: tables[i].id)
            },
            groupProducts: {},
            areaBindings: {}),
        spots: [
          BlueprintObjectModel(
              id: 11, state: 'ordered', orderProductTicket: 101),
          BlueprintObjectModel(id: 12, state: 'available'),
          BlueprintObjectModel(id: 13, state: 'selected')
        ],
        tickets: [
          TicketModel(id: 51, ticketSymbol: 'T51', state: 'ordered')
        ],
        orderProductTickets: [
          OrderProductTicketModel(id: 101, ticketId: 51)
        ],
        products: [
          ProductModel(
              id: 1,
              title: 'Seat',
              price: 100,
              productTypeString: ProductModel.spotType)
        ]);
    source.layoutResources = blueprintPreparedResourcesFixture(document);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pumpAndSettle();
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1400, 0));
    final hoveredRow =
        find.byKey(ValueKey('commercial-table-${tables.first.id}'));
    await mouse.moveTo(tester.getCenter(hoveredRow));
    await tester.pump();
    expect(editor.controller.hoveredIds, contains(seats.first.id));
    expect(editor.controller.selection, isEmpty);
    expect(editor.controller.canUndo, isFalse);
    await mouse.moveTo(const Offset(1400, 0));
    await tester.pump();
    expect(editor.controller.hoveredIds, isEmpty);
    await mouse.removePointer();
    editor.onViewSelectionChanged!({for (final seat in seats) seat.id});
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    for (final table in tables) {
      final row = find.byKey(ValueKey('commercial-table-${table.id}'));
      expect(tester.widget<ListTile>(row).selected, isTrue);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('commercial-detail-panel')),
              matching: find.text(table.label)),
          findsOneWidget);
    }
    final block = find.byKey(const ValueKey('blueprint-toggle-blocked'));
    await tester.tap(block);
    await tester.pumpAndSettle();
    final operationPanel =
        find.byKey(const ValueKey('blueprint-operation-panel'));
    expect(operationPanel, findsOneWidget);
    expect(editor.controller.canUndo, isFalse,
        reason: 'Entering block mode must not change any seat');
    await tester.tap(find.byKey(const ValueKey('blueprint-cancel-operation')));
    await tester.pumpAndSettle();
    expect(operationPanel, findsNothing);
    expect(editor.controller.canUndo, isFalse);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {seats[1].id});
    await tester.tap(find.byKey(const ValueKey('blueprint-confirm-operation')));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.unblockSeats), findsOneWidget);
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: operationPanel,
            matching: find.text(BlueprintStrings.unblockSeats)),
        findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('blueprint-confirm-operation')));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.blockSeats), findsOneWidget);
    editor.controller.undo();
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.unblockSeats), findsOneWidget);
    editor.controller.undo();
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.blockSeats), findsOneWidget);
    var previewReads = 0;
    final cancellations = <Map<String, dynamic>>[];
    final submittedReleases = <Map<String, dynamic>>[];
    final snapshot = List.filled(64, 'a').join();
    pickerResponse = (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      late Map<String, dynamic> response;
      if (request.url.path.endsWith('/preview_blueprint_hold_release')) {
        previewReads++;
        expect(body['p_spots'], [13]);
        response = {
          'occasionId': 1,
          'blueprintId': 1,
          'layoutRevision': 1,
          'requestedSpotIds': [13],
          'affectedSpotIds': [13, 14],
          'holdSnapshot': snapshot,
          'activeHoldCount': 2,
          'canApply': true,
          'seats': [
            {'spotId': 13, 'title': 'Seat 3', 'state': 'selected'},
            {'spotId': 14, 'title': 'Confirmed companion', 'state': 'selected'},
          ],
        };
      } else if (request.url.path
          .endsWith('/preview_blueprint_ticket_cancellation')) {
        response = {
          'occasionId': 1,
          'blueprintId': 1,
          'requestedSpotIds': body['p_spots'],
          'affectedSpotIds': [11],
          'ticketIds': [51],
          'blueprints': [
            {'id': 1, 'revision': 1}
          ],
          'confirmationHash': snapshot,
          'seats': [
            {
              'spotId': 11,
              'blueprintId': 1,
              'title': 'Reviewed ticket seat',
              'ticketId': 51,
              'orderId': 61,
              'state': 'paid'
            }
          ],
          'orders': [
            {
              'orderId': 61,
              'beforeAmount': '100.00',
              'afterAmount': '100.00',
              'delta': '0.00',
              'currencyCode': 'CZK',
              'beforeState': 'paid',
              'afterState': 'storno'
            }
          ]
        };
      } else if (request.url.path.endsWith('/cancel_blueprint_tickets')) {
        cancellations.add(body);
        response = commandResponseFixture(body['p_command_id'] as String,
            data: {'cancelledOrderIds': [], 'updatedOrders': []});
      } else if (request.url.path.endsWith('/release_blueprint_holds')) {
        submittedReleases.add(body);
        response =
            commandResponseFixture(body['p_command_id'] as String, data: {
          'spotIds': [13, 14]
        });
      } else {
        throw StateError('Unexpected UI operation: ${request.url.path}');
      }
      return http.Response(jsonEncode(response), 200,
          headers: {'content-type': 'application/json'}, request: request);
    };
    final release = find.byKey(const ValueKey('commercial-release-holds'));
    await tester.ensureVisible(release);
    Future<void> openReleaseConfirmation() async {
      for (var attempt = 0;
          attempt < 10 &&
              tester.widget<OutlinedButton>(release).onPressed == null;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      expect(tester.widget<OutlinedButton>(release).onPressed, isNotNull,
          reason: 'The previous cancelled operation must finish before retry');
      // The real durable journal must start in the real async zone, just as
      // filesystem-backed fixture cases elsewhere in this suite.
      await tester.runAsync(() => tester.tap(release));
      // Advance fake-async work before yielding to the real HTTP continuation.
      // pumpAndSettle alone can finish before an RPC schedules the dialog frame.
      for (var attempt = 0;
          attempt < 10 &&
              find
                  .text(BlueprintStrings.releaseTemporaryReservationConfirm)
                  .evaluate()
                  .isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();
    }

    await openReleaseConfirmation();
    expect(previewReads, 1,
        reason: 'The actual RPC preview completes before confirmation');
    expect(find.text(BlueprintStrings.releaseTemporaryReservationConfirm),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
    expect(find.text('Confirmed companion'), findsOneWidget);
    expect(find.text(BlueprintStrings.releaseTemporaryReservationPreview(2, 2)),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(submittedReleases, isEmpty, reason: 'Cancel must keep every hold');
    await openReleaseConfirmation();
    // A local overlay change after confirmation cannot silently narrow the intent.
    source.spots!.last.setSeatState(BlueprintSeatState.available);
    await tester.runAsync(() => tester.tap(find.widgetWithText(
        ElevatedButton, BlueprintStrings.releaseTemporaryReservation)));
    for (var attempt = 0;
        attempt < 10 && submittedReleases.isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pumpAndSettle();
    expect(previewReads, 2);
    expect(submittedReleases, hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
    expect(submittedReleases.single['p_spots'], [13]);
    expect(submittedReleases.single['p_affected_spots'], [13, 14]);
    expect(submittedReleases.single['p_hold_snapshot'], snapshot);
    expect(
        tester
            .widgetList<BlueprintEditorFeedback>(
                find.byType(BlueprintEditorFeedback))
            .map((feedback) => feedback.message),
        everyElement(isNull),
        reason:
            'The command must complete its journal and refresh without a UI error');
    tester
        .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
        .onViewSelectionChanged!({for (final seat in seats) seat.id});
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('commercial-cancel-tickets'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Reviewed ticket seat'), findsOneWidget);
    expect(find.textContaining('51'), findsWidgets);
    // Dismissal must not send cancellation I/O (only preview/release is allowed).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(source.spots!.first.orderProductTicket, 101);
    expect(cancellations, isEmpty);
    expect(tester.takeException(), isNull);
    tester
        .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
        .onViewSelectionChanged!({for (final seat in seats) seat.id});
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('blueprint-start-order')));
    await tester.tap(find.byKey(const ValueKey('blueprint-start-order')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {seats[1].id, seats[2].id});
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blueprint-start-swap')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        isEmpty,
        reason: 'A three-seat selection must not silently choose a swap pair');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    editor.onViewSelectionChanged!({seats.first.id, seats.last.id});
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blueprint-start-swap')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {seats.first.id, seats.last.id});
    var swapPreviews = 0;
    Map<String, dynamic>? approvedSwap;
    final swapWrites = <Map<String, dynamic>>[];
    pickerResponse = (request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      late Map<String, dynamic> response;
      if (request.url.path.endsWith('/preview_blueprint_seat_swap')) {
        swapPreviews++;
        expect({body['p_first'], body['p_second']}, {11, 13});
        response = blueprintSwapPreviewFixture();
        if (body['p_first'] == 13) {
          final sourceIds = response['sourceSpotIds'];
          response['sourceSpotIds'] = response['targetSpotIds'];
          response['targetSpotIds'] = sourceIds;
        }
        response['firstSpotId'] = body['p_first'];
        response['secondSpotId'] = body['p_second'];
        approvedSwap = response;
      } else if (request.url.path.endsWith('/swap_blueprint_seats')) {
        swapWrites.add(body);
        response = commandResponseFixture(body['p_command_id'] as String);
      } else {
        throw StateError('Unexpected swap request: ${request.url.path}');
      }
      return http.Response(jsonEncode(response), 200,
          request: request, headers: {'content-type': 'application/json'});
    };
    final swapConfirm =
        find.byKey(const ValueKey('blueprint-confirm-operation'));
    Future<void> openSwap() async {
      for (var attempt = 0;
          attempt < 100 &&
              tester.widget<FilledButton>(swapConfirm).onPressed == null;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.runAsync(() => tester.tap(swapConfirm));
      for (var attempt = 0;
          attempt < 100 && find.text('Source companion').evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pumpAndSettle();
      expect(find.text('Source companion'), findsOneWidget,
          reason: 'Preview calls: $swapPreviews; ' +
              tester
                  .widgetList<Text>(find.byType(Text))
                  .map((t) => t.data)
                  .join(' | '));
      expect(find.text('Destination companion'), findsOneWidget);
      expect(find.text(BlueprintStrings.swapServerNotice), findsOneWidget);
    }

    await openSwap();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(swapWrites, isEmpty);
    await openSwap();
    // Selection can change while a modal is open; the approved payload cannot.
    tester
        .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
        .onViewSelectionChanged!({seats[1].id, seats[2].id});
    final dialog = find.byType(AlertDialog);
    await tester.runAsync(() => tester.tap(find.descendant(
        of: dialog,
        matching: find.widgetWithText(
            FilledButton, BlueprintStrings.legendSwapSeats))));
    for (var attempt = 0;
        attempt < 100 &&
            (swapWrites.isEmpty ||
                find
                    .byKey(const ValueKey('blueprint-confirm-operation'))
                    .evaluate()
                    .isNotEmpty);
        attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pumpAndSettle();
    expect(swapPreviews, 2);
    expect(swapWrites, hasLength(1));
    expect(swapWrites.single['p_first'], approvedSwap!['firstSpotId']);
    expect(swapWrites.single['p_second'], approvedSwap!['secondSpotId']);
    expect(swapWrites.single['p_source_spots'], approvedSwap!['sourceSpotIds']);
    expect(swapWrites.single['p_target_spots'], approvedSwap!['targetSpotIds']);
    expect(swapWrites.single['p_confirmation_hash'],
        blueprintSwapPreviewFixture()['confirmationHash']);
    expect(
        tester
            .widgetList<BlueprintEditorFeedback>(
                find.byType(BlueprintEditorFeedback))
            .map((f) => f.message),
        everyElement(isNull));
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.occasionsWrite: true},
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: false));
    editor.onViewSelectionChanged!({seats.first.id});
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('commercial-cancel-tickets')), findsNothing);
  });

  for (final outcome in ['merge', 'removed', 'replaced', 'reload', 'failed']) {
    testWidgetsWithEnvironment(
        () => environment, 'host delayed image load guards $outcome resources',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC');
      final hash = sha256.convert(bytes).toString();
      final ref = 'image:$hash';
      final otherBytes = [...bytes, 0];
      final otherHash = sha256.convert(otherBytes).toString();
      final otherRef = 'image:$otherHash';
      final manifest = <String, dynamic>{
        'hash': hash,
        'url': 'https://images.example.test/old.png',
        'width': 2,
        'height': 2,
        'mimeType': 'image/png',
        'byteLength': bytes.length
      };
      final fixture = jsonDecode(
          File('test/fixtures/blueprint/canonical-text-scene.json')
              .readAsStringSync()) as Map;
      final document = VenueLayoutDocument.fromJson(
          Map<String, dynamic>.from(fixture['document'] as Map));
      final resources = Map<String, dynamic>.from(fixture['resources'] as Map);
      final source = BlueprintModel(
          layoutResources: {
            ...resources,
            'assets': {ref: manifest}
          },
          layoutSnapshot: BlueprintLayoutSnapshot(
              blueprintId: 1,
              occasionId: 1,
              title: 'Images',
              revision: 1,
              document: document));
      final response = Completer<http.Response>();
      var requests = 0;
      final resolver =
          BlueprintLayoutAssetResolver(client: MockClient((request) {
        if (request.url.path == '/other.png')
          return Future.value(http.Response.bytes(otherBytes, 200));
        requests++;
        return requests == 1
            ? response.future
            : Future.value(http.Response.bytes(bytes, 200));
      }));
      await environment.pumpWidget(
          tester,
          MaterialApp(
              home: BlueprintLayoutHost(
                  key: const ValueKey('old-host'),
                  source: source,
                  reload: () async => source,
                  assetResolver: resolver)));
      await tester.pump();
      final controller = tester
          .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
          .controller;
      final latestAssets = <String, dynamic>{
        if (outcome != 'removed')
          ref: outcome == 'replaced'
              ? {...manifest, 'url': 'https://images.example.test/replaced.png'}
              : manifest,
        otherRef: {
          ...manifest,
          'hash': otherHash,
          'byteLength': otherBytes.length,
          'url': 'https://images.example.test/other.png'
        },
      };
      expect(
          controller
              .setResources({...controller.resources, 'assets': latestAssets}),
          isTrue);
      final latest = controller.resources;
      if (outcome == 'reload') {
        final fresh = BlueprintModel(
            layoutResources: resources, layoutSnapshot: source.layoutSnapshot);
        await environment.pumpWidget(
            tester,
            MaterialApp(
                home: BlueprintLayoutHost(
                    key: const ValueKey('new-host'),
                    source: fresh,
                    reload: () async => fresh)));
      }
      response.complete(
          http.Response.bytes(bytes, outcome == 'failed' ? 500 : 200));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      if (outcome == 'reload') {
        final freshController = tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .controller;
        expect(freshController.resources['assets'], resources['assets'] ?? {});
        expect(tester.takeException(), isNull);
        return;
      }
      if (outcome == 'failed') {
        expect(controller.resources, latest);
        await tester.runAsync(() async {
          final retry = tester.widget<TextButton>(
              find.widgetWithText(TextButton, CommonStrings.retry));
          retry.onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
      }
      expect(controller.resources['assets'], latestAssets);
      expect(controller.resources['fontFamilies'], resources['fontFamilies']);
      expect(controller.resources['textLayouts'], resources['textLayouts']);
      expect((controller.resources['images'] as Map).containsKey(ref),
          outcome == 'merge' || outcome == 'failed');
      expect(controller.dirty, isFalse);
      expect(controller.canUndo, isFalse);
    });
  }
  for (final outcome in [
    'reservations',
    'edit again',
    'repeated',
    'disposed'
  ]) {
    testWidgetsWithEnvironment(() => environment,
        'mode switch keeps composed text local until Save: $outcome',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rights = RightsService.occasionLinkModelNotifier.value;
      RightsService.occasionLinkModelNotifier.value =
          OccasionLinkModel(capabilities: {
        AuthorizationCapabilities.occasionsWrite: true,
        AuthorizationCapabilities.ordersWrite: true
      }, isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
      final fixture = jsonDecode(
          File('test/fixtures/blueprint/canonical-text-scene.json')
              .readAsStringSync()) as Map;
      final document = VenueLayoutDocument.fromJson(
          Map<String, dynamic>.from(fixture['document'] as Map));
      final resources = Map<String, dynamic>.from(fixture['resources'] as Map);
      var batches = 0;
      final provider = await tester.runAsync(() => BlueprintTextResources.load(
              1, service: TicketLayoutService(transport: (body) async {
            if (body['mode'] == 'font') {
              final catalog = jsonDecode(File(
                      'supabase/functions/_shared/ticket-assets/font-catalog.json')
                  .readAsStringSync())['fonts'] as List;
              final face =
                  catalog.firstWhere((entry) => entry['id'] == body['fontId']);
              final bytes = File(
                      'test/fixtures/ticket_fonts/${face['family'].replaceAll(' ', '-')}.ttf')
                  .readAsBytesSync();
              return {
                'id': face['id'],
                'family': face['family'],
                'weight': face['weight'],
                'font': base64Encode(bytes),
                'metrics': jsonDecode(
                    File('test/fixtures/ticket_layout/resolve.json')
                        .readAsStringSync())['metrics']
              };
            }
            batches++;
            throw StateError('Vector generation must wait for explicit save');
          })));
      await tester.runAsync(() => provider!.loadFace(
          (resources['fontFamilies'] as Map).values.first['faces']['400:normal']
              as String));
      final source = BlueprintModel(
          layoutResources: resources,
          layoutSnapshot: BlueprintLayoutSnapshot(
              blueprintId: 1,
              occasionId: 1,
              title: 'Transition',
              revision: 1,
              document: document));
      await environment.pumpWidget(
          tester,
          MaterialApp(
              home: BlueprintLayoutHost(
                  source: source,
                  reload: () async => source,
                  loadTextResources: () async => provider!)));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('blueprint-edit-mode')));
      await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
          .controller;
      expect(
          compileScene(controller.document,
              resources: controller.resources)['issues'],
          isEmpty);
      await doubleTapLayout(tester, const Offset(200, 180));
      await tester.pump();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      final input = find.byKey(const ValueKey('layout-inline-label'));
      expect(input, findsOneWidget);
      await tester.showKeyboard(input);
      tester.testTextInput.updateEditingValue(const TextEditingValue(
          text: 'Completed composing text',
          selection: TextSelection.collapsed(offset: 24),
          composing: TextRange(start: 0, end: 24)));
      await tester.pump();
      expect(controller.document.toJson(), document.toJson(),
          reason: 'composition has not yet committed into the valid scene');
      final dynamic view =
          tester.widget(find.byKey(const ValueKey('blueprint-screen-mode')));
      final modes = view.selected.toSet();
      modes.clear();
      modes.add(view.segments.first.value);
      view.onSelectionChanged(modes);
      view.onSelectionChanged(modes);
      await tester.pump();
      await tester.pump();
      if (outcome == 'disposed') {
        await environment.pumpWidget(tester, const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(batches, 0);
        expect(tester.takeException(), isNull);
        return;
      }
      await tester.pumpAndSettle();
      var editor =
          tester.widget<BlueprintPlanEditor>(find.byType(BlueprintPlanEditor));
      expect(editor.busy, isFalse);
      expect(editor.interactionEnabled, isFalse);
      expect(editor.nativeTextPreview, isTrue);
      expect(controller.document.nodes.first.properties['text'],
          'Completed composing text');
      final native = (layoutPainter(tester).scene['items'] as List)
          .where((item) =>
              item['kind'] == 'nativeText' &&
              item['nodeId'] == document.nodes.first.id)
          .single;
      expect(native['nativeParagraph'].text.toPlainText(),
          'Completed composing text');
      final beforeDrag = controller.document.toJson();
      await tester.drag(layoutCanvas(), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.toJson(), beforeDrag,
          reason:
              'Local draft rendering grants no geometry editing in reservations');
      if (outcome == 'edit again') {
        await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
        await tester.pumpAndSettle();
        editor = tester
            .widget<BlueprintPlanEditor>(find.byType(BlueprintPlanEditor));
        expect(editor.interactionEnabled, isTrue);
        expect(controller.document.nodes.first.properties['text'],
            'Completed composing text');
      }
      if (outcome == 'repeated') {
        view.onSelectionChanged(modes);
        await tester.pumpAndSettle();
      }
      expect(batches, 0,
          reason:
              'Composition, mode changes and canvas gestures never request canonical vectors');
      expect(source.layoutSnapshot!.document.toJson(), document.toJson(),
          reason: 'The saved plan remains unchanged');
      expect(source.layoutSnapshot!.revision, 1);
      expect(controller.dirty, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgetsWithEnvironment(() => environment,
      'setup and existing occasion share plan editor typography graphics and history',
      (tester) async {
    final fixture = jsonDecode(
        File('test/fixtures/blueprint/canonical-text-scene.json')
            .readAsStringSync()) as Map;
    final document = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(fixture['document'] as Map));
    final resources = Map<String, dynamic>.from(fixture['resources'] as Map);
    await tester.runAsync(TicketFontCatalog.loadFamilies);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(capabilities: {
      AuthorizationCapabilities.occasionsWrite: true,
      AuthorizationCapabilities.ordersWrite: true
    }, isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final source = BlueprintModel(
        layoutResources: resources,
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Shared editor',
            revision: 1,
            document: document));
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pump(const Duration(milliseconds: 200));
    final shared =
        tester.widget<BlueprintPlanEditor>(find.byType(BlueprintPlanEditor));
    await tester.runAsync(shared.loadTextResources!);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BlueprintPlanEditor), findsOneWidget);
    expect(
        find.widgetWithText(
            ListTile,
            VenueLayoutStrings.text(
                tester.element(find.byType(BlueprintPlanEditor)),
                'Insert image / SVG')),
        findsOneWidget);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .fontPickerBuilder,
        isNotNull);
    final existing =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(existing.inlineTextStyleBuilder, isNotNull);
    expect(existing.globalFontPickerBuilder, isNotNull);
    await environment.pumpWidget(tester, const SizedBox.shrink());
    final batches = <Map<String, dynamic>>[];
    final provider = await tester.runAsync(() =>
        BlueprintTextResources.forSetupDraft('draft-id',
            service: TicketLayoutService(transport: (body) async {
          expectSync(body['setupDraftId'], 'draft-id');
          if (body['mode'] == 'font')
            throw StateError(
                'Native font raster is outside this transport fixture');
          expectSync(body['mode'], 'layout-text');
          final batch = Map<String, dynamic>.from(body['batch'] as Map);
          batches.add(batch);
          return {
            'protocol': 2,
            'fontFamilies': resources['fontFamilies'],
            'numberSymbols': {},
            'textLayouts': {
              for (final raw in batch['requests'] as List)
                LayoutTextRequest(Map<String, dynamic>.from(raw)).id: {
                  'id': LayoutTextRequest(Map<String, dynamic>.from(raw)).id,
                  'descriptor':
                      LayoutTextRequest(Map<String, dynamic>.from(raw))
                          .resourceDescriptor,
                  'path': [
                    ['M', 0, 0],
                    ['L', 10, 10]
                  ],
                  'clip': raw['box'],
                },
            }
          };
        })));
    VenueLayoutDocument? saved;
    Map<String, dynamic>? savedResources;
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutDemo(
                initialDocument: document,
                initialResources: resources,
                unitId: 7,
                prepareResources: (document, current) async {
                  final prepared =
                      await BlueprintTextPreparation(provider!.prepareTextBatch)
                          .prepareSnapshot(
                              document,
                              {
                                for (final family in provider.families)
                                  family['id'] as String: family
                              },
                              current);
                  savedResources = prepared;
                  return prepared;
                },
                onSave: (document) async {
                  saved = document;
                },
                loadTextResources: () async => provider!)));
    await tester.pumpAndSettle();
    expect(find.byType(BlueprintPlanEditor), findsOneWidget);
    expect(
        find.widgetWithText(
            ListTile,
            VenueLayoutStrings.text(
                tester.element(find.byType(BlueprintPlanEditor)),
                'Insert image / SVG')),
        findsOneWidget);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .fontPickerBuilder,
        isNotNull);
    final setup =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(setup.inlineTextStyleBuilder, isNotNull);
    expect(setup.globalFontPickerBuilder, isNotNull);
    expect(batches, isEmpty, reason: 'persisted prepared paths are reused');
    final text = setup.controller.document.nodes.first;
    expect(
        setup.controller.apply(document.copyWith(nodes: [
          text.copyWith(properties: {
            ...text.properties,
            'text': 'Changed whole paragraph'
          }),
          ...document.nodes.skip(1),
        ])),
        isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(batches, isEmpty,
        reason: 'native editing never dispatches vector preparation');
    final saving =
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).onSave();
    await tester.pump();
    await saving;
    expect(saved!.toJson(), setup.controller.document.toJson());
    for (final entry in (savedResources!['textLayouts'] as Map).entries) {
      expect((setup.controller.resources['textLayouts'] as Map)[entry.key],
          entry.value);
    }
    expect(batches, hasLength(1),
        reason: 'only explicit save prepares the captured whole paragraph');
    setup.controller.undo();
    await tester.pumpAndSettle();
    expect(setup.controller.document.toJson(), document.toJson());
    expect(
        compileScene(setup.controller.document,
            resources: setup.controller.resources)['issues'],
        isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgetsWithEnvironment(() => environment,
      'blueprint V2 order retries analysis and suppresses duplicate submits',
      (tester) async {
    var analyses = 0;
    var submissions = 0;
    final pending = Completer<void>();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: BlueprintCreateOrderDialog(
          request: seatOrderRequestFixture(),
          commands: seatOrderCommandsFixture(onRequirements: () async {
            if (++analyses == 1) throw StateError('offline');
          }, onCreate: (_) {
            submissions++;
            return pending.future;
          }),
        ))));
    await tester.pumpAndSettle();
    expect(analyses, 1);
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();
    expect(analyses, 2);
    await tester.enterText(
        find.byType(TextFormField, skipOffstage: false), 'local@example.test');
    await tester.tap(find.widgetWithText(
        ElevatedButton, 'FeatureBlueprint.orderReview'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(ElevatedButton, BlueprintStrings.confirmOrder));
    await tester.pump();
    expect(submissions, 1);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<TextFormField>(
                find.byType(TextFormField, skipOffstage: false))
            .enabled,
        isFalse);
    pending.completeError(StateError('reservation changed'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, CommonStrings.retry),
        findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.byType(TextFormField, skipOffstage: false))
            .controller!
            .text,
        'local@example.test');
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'blueprint V2 catalog editor fits narrow screen and rejects empty title',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: EditProductDialog(
                    product: ProductModel(title: '', price: 100),
                    isCreating: false,
                    affectedSeatCount: 12))));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.catalogSaveNotice), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.save));
    await tester.pumpAndSettle();
    expect(find.text(CommonStrings.fieldCannotBeEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgetsWithEnvironment(() => environment,
      'blueprint inspector renames the single canonical native table',
      (tester) async {
    await tester.runAsync(TicketFontCatalog.load);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(capabilities: {
      AuthorizationCapabilities.occasionsWrite: true,
      AuthorizationCapabilities.ordersWrite: true
    }, isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        surface: {'type': 'rect'},
        x: 400,
        y: 400,
        width: 200,
        height: 100,
        label: 'S7');
    final original = VenueLayoutDocument(nodes: [table]);
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Rename',
            revision: 1,
            document: original,
            seatBindings: {},
            groupProducts: {table.id: 1}));
    source.layoutResources =
        blueprintPreparedResourcesFixture(source.layoutSnapshot!.document);
    var vectorRequests = 0;
    final provider = await tester.runAsync(() => BlueprintTextResources.load(1,
            service: TicketLayoutService(transport: (body) async {
          if (body['mode'] != 'font') vectorRequests++;
          return blueprintNativeFontReplyFixture(body);
        })));
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source,
                reload: () async => source,
                loadTextResources: () async => provider!)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const ValueKey('layout-tool-Select')), findsNothing);
    expect(find.byType(FontFamilyPicker), findsNothing);
    expect(find.byKey(const ValueKey('layout-tool-Pan')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const ValueKey('layout-tool-Select')), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-tool-Pan')), findsOneWidget);
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    // The same native table owns the visible and commercial name.
    editor.controller.select({table.id});
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final catalog = tester.widget<FutureBuilder<BlueprintTextResources>>(
        find.byType(FutureBuilder<BlueprintTextResources>));
    await tester.runAsync(() => catalog.future!);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final fonts =
        tester.widget<FontFamilyPicker>(find.byType(FontFamilyPicker));
    expect(fonts.families, containsAll(['Zeyada', 'Roboto Slab', 'Futura PT']));
    expect(fonts.families.length, greaterThan(1000));
    expect(editor.globalFontPickerBuilder, isNotNull);
    // The plan-style dialog receives the same full catalog, independently of
    // the currently selected object and of the generic Text scope.
    showDialog<void>(
      context: tester.element(find.byType(VenueLayoutEditor)),
      builder: (context) => Dialog(
        child: editor.globalFontPickerBuilder!(context, 'table'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final globalFonts =
        tester.widgetList<FontFamilyPicker>(find.byType(FontFamilyPicker)).last;
    expect(globalFonts.families, fonts.families);
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Name');
    await tester.enterText(name, '  Front table  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(editor.controller.document.nodes.map((n) => n.label),
        everyElement('Front table'));
    expect(source.layoutSnapshot!.document, same(original));
    expect(source.layoutSnapshot!.revision, 1);
    expect(vectorRequests, 0,
        reason: 'Renaming uses the loaded native font until explicit Save');
    expect(editor.controller.dirty, isTrue);
    expect(
        (layoutPainter(tester).scene['items'] as List)
            .where((item) => item['kind'] == 'nativeText')
            .isNotEmpty,
        isTrue);

    await tester.enterText(name, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(editor.controller.document.nodes.map((n) => n.label),
        everyElement('Front table'));
    editor.controller.undo();
    await tester.pump();
    expect(editor.controller.document, same(original));
  });
  testWidgetsWithEnvironment(() => environment,
      'blueprint host history shortcuts survive semantic inspector activation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(capabilities: {
      AuthorizationCapabilities.occasionsWrite: true,
      AuthorizationCapabilities.ordersWrite: true
    }, isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        surface: {'type': 'rect'},
        x: 400,
        y: 400,
        width: 200,
        height: 100,
        label: 'S7',
        style: {
          'label': {'weight': 700}
        });
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'History',
            revision: 1,
            document: VenueLayoutDocument(nodes: [table]),
            seatBindings: {},
            groupProducts: {}));
    source.layoutResources =
        blueprintPreparedResourcesFixture(source.layoutSnapshot!.document);
    final provider = await tester.runAsync(() => BlueprintTextResources.load(1,
            service: TicketLayoutService(transport: (body) async {
          final batch = body['batch'] as Map;
          return {
            'protocol': 2,
            'fontFamilies': source.layoutResources['fontFamilies'],
            'numberSymbols': {},
            'textLayouts': {
              for (final raw in batch['requests'] as List)
                LayoutTextRequest(Map<String, dynamic>.from(raw)).id: {
                  'id': LayoutTextRequest(Map<String, dynamic>.from(raw)).id,
                  'descriptor':
                      LayoutTextRequest(Map<String, dynamic>.from(raw))
                          .resourceDescriptor,
                  'path': [
                    ['M', 0, 0],
                    ['L', 10, 10]
                  ],
                  'clip': raw['box'],
                },
            },
          };
        })));
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source,
                reload: () async => source,
                loadTextResources: () async => provider!)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    editor.controller.select({table.id});
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final hostFocus = tester
        .widgetList<Focus>(find.byType(Focus))
        .singleWhere(
            (focus) => focus.focusNode?.debugLabel == 'Blueprint host actions')
        .focusNode!;
    expect(hostFocus.hasPrimaryFocus, isTrue);
    final bold = find.byIcon(Icons.format_bold);
    await tester.ensureVisible(bold);
    final semantics = tester.ensureSemantics();
    try {
      tester.binding.renderViews.single.owner!.semanticsOwner!
          .performAction(tester.getSemantics(bold).id, SemanticsAction.tap);
      await tester.pump();
    } finally {
      semantics.dispose();
    }
    bool isBold() =>
        (editor.controller.document.nodes.single.style['label']
            as Map?)?['weight'] ==
        700;
    expect(isBold(), isFalse);
    expect(hostFocus.hasPrimaryFocus, isTrue);
    Future<void> shortcut(
        {bool meta = false,
        bool shift = false,
        LogicalKeyboardKey key = LogicalKeyboardKey.keyZ}) async {
      final modifier =
          meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    await shortcut();
    expect(isBold(), isTrue);
    await shortcut(meta: true, shift: true);
    expect(isBold(), isFalse);
    await shortcut(meta: true);
    expect(isBold(), isTrue);
    await shortcut(key: LogicalKeyboardKey.keyY);
    expect(isBold(), isFalse);
    await tester
        .tap(find.widgetWithText(ListTile, BlueprintStrings.background));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await shortcut();
    expect(isBold(), isFalse, reason: 'An open modal owns its keyboard scope');
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('blueprint-background-picker')),
        matching: find.byIcon(Icons.close)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    hostFocus.requestFocus();
    await tester.pump();
    await shortcut();
    expect(isBold(), isTrue);
    await shortcut(key: LogicalKeyboardKey.keyY);
    final textInput = tester.widget<EditableText>(find
        .descendant(
            of: find.byType(VenueLayoutEditor),
            matching: find.byType(EditableText))
        .first);
    textInput.focusNode.requestFocus();
    await tester.pump();
    await shortcut();
    expect(isBold(), isFalse, reason: 'Active text input keeps native undo');
    await tester.ensureVisible(
        find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await shortcut();
    expect(isBold(), isFalse, reason: 'Reservations must not undo plan edits');
  });
  testWidgetsWithEnvironment(() => environment,
      'blueprint V2 operational Escape and mode switch preserve geometry draft',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalRights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.occasionsWrite: true,
          AuthorizationCapabilities.ordersWrite: true
        },
        isAdmin: true,
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: true));
    addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = originalRights);
    const id = '10000000-0000-4000-8000-000000000001';
    final snapshot = BlueprintLayoutSnapshot(
        blueprintId: 1,
        occasionId: 1,
        title: 'Local fixture',
        revision: 1,
        document: VenueLayoutDocument(nodes: [
          LayoutNode(
              id: '10000000-0000-4000-8000-000000000020',
              kind: 'capacityArea',
              label: 'Standing',
              x: 800,
              y: 400,
              width: 200,
              height: 200,
              properties: {'capacity': 20}),
          LayoutNode(
              id: id,
              kind: 'seat',
              parentId: '10000000-0000-4000-8000-000000000003',
              x: 100,
              y: 100,
              label: 'A1'),
          LayoutNode(
              id: '10000000-0000-4000-8000-000000000003',
              kind: 'table',
              surface: {'type': 'rect'},
              parentId: '10000000-0000-4000-8000-000000000002',
              label: 'Physical table'),
          LayoutNode(
              id: '10000000-0000-4000-8000-000000000010',
              kind: 'group',
              x: 100,
              y: 100,
              label: 'Group 10'),
          LayoutNode(
              id: '10000000-0000-4000-8000-000000000011',
              kind: 'table',
              surface: {'type': 'rect'},
              parentId: '10000000-0000-4000-8000-000000000010',
              x: 400,
              label: 'Physical table 10'),
          LayoutNode(
              id: '10000000-0000-4000-8000-000000000002',
              kind: 'group',
              x: 100,
              y: 100,
              label: 'Group 2'),
        ]),
        seatBindings: {
          id: const BlueprintSeatBinding(
              nodeId: id,
              spotId: 11,
              productId: 1,
              title: 'A1',
              groupNodeId: '10000000-0000-4000-8000-000000000002')
        },
        areaBindings: {
          '10000000-0000-4000-8000-000000000020': const BlueprintAreaBinding(
              nodeId: '10000000-0000-4000-8000-000000000020',
              inventoryContextId: 7,
              productId: 1)
        },
        groupProducts: {
          '10000000-0000-4000-8000-000000000002': 1,
          '10000000-0000-4000-8000-000000000010': 1
        });
    final source = BlueprintModel(layoutSnapshot: snapshot, products: [
      ProductModel(
          id: 1,
          title: 'Standard',
          price: 100,
          productTypeString: ProductModel.spotType),
      ProductModel(
          id: 2,
          title: 'Premium',
          price: 200,
          productTypeString: ProductModel.spotType)
    ], spots: [
      BlueprintObjectModel(id: 11, state: 'available')
    ]);
    source.layoutResources =
        blueprintPreparedResourcesFixture(source.layoutSnapshot!.document);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source,
                reload: () async => source,
                loadTextResources: () => BlueprintTextResources.load(1,
                    service: TicketLayoutService(
                        transport: blueprintNativeFontReplyFixture)))));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    Future<void> expectActionVisible(String key) async {
      final action = find.byKey(ValueKey(key));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      final badge = find.byType(EditorActionBar);
      if (badge.evaluate().isNotEmpty) {
        expect(tester.getRect(action).right,
            lessThanOrEqualTo(tester.getRect(badge).left));
      }
    }

    await expectActionVisible('blueprint-start-order');
    await expectActionVisible('blueprint-start-swap');
    final initialEditor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(initialEditor.interactionEnabled, isFalse);
    expect((initialEditor.seatPresentation[id] as Map)['fill'], '#267329FF');
    expect(initialEditor.controller.placementIssues, isEmpty);
    expect(find.byType(EditorActionBar), findsOneWidget);
    expect(find.byKey(const ValueKey('blueprint-reservations-panel')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('layout-palette')), findsNothing);
    final reservationScroll = find.descendant(
        of: find.byKey(const ValueKey('blueprint-reservations-panel')),
        matching: find.byType(SingleChildScrollView));
    expect(tester.getSize(reservationScroll).height, greaterThan(500));
    expect(find.text(BlueprintStrings.selectTableOrSeat), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.table_restaurant_outlined), findsNWidgets(2));
    final canvasState = tester.element(layoutCanvas());
    final originalDocument = initialEditor.controller.document;
    final groupRow = find.byKey(const ValueKey(
        'commercial-table-10000000-0000-4000-8000-000000000002'));
    final secondRow = find.byKey(const ValueKey(
        'commercial-table-10000000-0000-4000-8000-000000000010'));
    final areaRow = find.byKey(
        const ValueKey('commercial-area-10000000-0000-4000-8000-000000000020'));
    expect(
        find.descendant(
            of: areaRow, matching: find.byIcon(Icons.people_outline)),
        findsOneWidget);
    expect(find.descendant(of: areaRow, matching: find.text('(20)')),
        findsOneWidget);
    expect(tester.getTopLeft(areaRow).dy,
        lessThan(tester.getTopLeft(groupRow).dy));
    await tester.tap(areaRow);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('commercial-detail-panel')), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('commercial-area-product')));
    await tester.tap(find.byKey(const ValueKey('commercial-area-product')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        tester
            .widget<EditProductDialog>(find.byType(EditProductDialog))
            .product
            .id,
        1);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.ensureVisible(groupRow);
    await tester.tap(groupRow);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('commercial-detail-panel')), findsOneWidget);
    expect(find.text(BlueprintStrings.groupDefaultProduct), findsOneWidget);
    expect(find.text(BlueprintStrings.statusUniform), findsOneWidget);
    expect(find.text(BlueprintStrings.uniformViewHelp), findsNothing);
    expect(find.byKey(ValueKey('commercial-seat-$id')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('commercial-individual-seats')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byIcon(Icons.event_seat), findsOneWidget);
    final seatRow = find.byKey(ValueKey('commercial-seat-$id'));
    await tester
        .tap(find.descendant(of: seatRow, matching: find.byType(IconButton)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(SelectProductDialog), findsOneWidget);
    expect(
        tester
            .widget<SelectProductDialog>(find.byType(SelectProductDialog))
            .currentProductId,
        1);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(seatRow);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text(BlueprintStrings.selectProduct), findsOneWidget);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {id});
    await tester.tap(find.byKey(const ValueKey('commercial-detail-back')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text(BlueprintStrings.groupDefaultProduct), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.ensureVisible(secondRow);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(secondRow);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('commercial-detail-panel')), findsOneWidget);
    expect(initialEditor.controller.selection, isEmpty);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {
          '10000000-0000-4000-8000-000000000002',
          '10000000-0000-4000-8000-000000000010'
        });
    await tester.ensureVisible(
        find.byKey(const ValueKey('commercial-selection-product')));
    await tester
        .tap(find.byKey(const ValueKey('commercial-selection-product')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Premium'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(initialEditor.controller.document, same(originalDocument));
    expect(initialEditor.controller.dirty, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('commercial-undo')));
    await tester.tap(find.byKey(const ValueKey('commercial-undo')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(initialEditor.controller.dirty, isFalse);
    tester
        .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
        .onViewSelectionChanged!({id});
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text(BlueprintStrings.selectProduct), findsOneWidget);
    expect(initialEditor.controller.selection, isEmpty);
    final beforeDrag = initialEditor.controller.document.toJson();
    await tester.drag(layoutCanvas(), const Offset(80, 0));
    await tester.pump();
    expect(initialEditor.controller.document.toJson(), beforeDrag,
        reason: 'Reservation drags cannot edit geometry');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    final toolbar = find.byKey(const ValueKey('layout-editor-toolbar'));
    expect(toolbar, findsOneWidget);
    expect(tester.getSize(toolbar).height, lessThanOrEqualTo(112));
    expect(find.descendant(of: toolbar, matching: find.byType(EditorActionBar)),
        findsOneWidget);
    expect(tester.widget<EditorActionBar>(find.byType(EditorActionBar)).inline,
        isTrue);
    expect(find.byType(BottomAppBar), findsNothing);
    expect(
        tester.getRect(toolbar).contains(tester
            .getCenter(find.widgetWithText(FilledButton, CommonStrings.save))),
        isTrue);
    expect(
        tester.getSize(find.byType(VenueLayoutEditor)).height,
        greaterThan(
            tester.view.physicalSize.height / tester.view.devicePixelRatio -
                70));
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect((editor.seatPresentation[id] as Map).containsKey('fill'), isFalse,
        reason:
            'Geometry styles must not be hidden by reservation status colors');
    await tester
        .tap(find.widgetWithText(ListTile, BlueprintStrings.background));
    await tester.pump(const Duration(milliseconds: 350));
    final backgroundDialog =
        find.byKey(const ValueKey('blueprint-background-picker'));
    expect(backgroundDialog, findsOneWidget);
    expect(
        find.descendant(
            of: backgroundDialog,
            matching: find.byType(LinearProgressIndicator)),
        findsNothing,
        reason: 'Choosing a background is not an upload');
    await tester.tap(find.descendant(
        of: backgroundDialog, matching: find.byIcon(Icons.close)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text(BlueprintStrings.selectProduct), findsNothing);
    expect(find.byKey(const ValueKey('blueprint-reservations-panel')),
        findsNothing);
    expect(editor.readOnlyLabelNodeIds, contains(id));
    final overlappingSeatId = newLayoutId();
    final originalSeat =
        editor.controller.document.nodes.singleWhere((node) => node.id == id);
    editor.controller.beginGesture();
    editor.controller.apply(editor.controller.document.copyWith(nodes: [
      ...editor.controller.document.nodes,
      LayoutNode.fromJson({...originalSeat.toJson(), 'id': overlappingSeatId}),
    ]));
    editor.controller.commitGesture();
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    expect(find.text(BlueprintStrings.placementInvalid), findsOneWidget);
    expect(editor.controller.placementWarningIds,
        containsAll([id, overlappingSeatId]));
    editor.controller.undo();
    await tester.pump();
    editor.controller.beginGesture();
    editor.controller.apply(editor.controller.document.copyWith(
        canvas: {...editor.controller.document.canvas, 'width': 2600}));
    await tester.pump();
    editor.controller.commitGesture();
    final draft = editor.controller.document;
    await tester.ensureVisible(
        find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(tester.element(layoutCanvas()), same(canvasState));
    expect(find.byType(EditorActionBar), findsOneWidget);
    expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isTrue);
    await expectActionVisible('blueprint-start-order');
    await expectActionVisible('blueprint-start-swap');
    final semantics = tester.ensureSemantics();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        tester
            .getSemantics(find.byKey(const ValueKey('blueprint-start-order')))
            .id,
        SemanticsAction.tap);
    await tester.pump();
    expect(find.text(BlueprintStrings.confirmOrder), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('blueprint-start-order')), findsOneWidget,
        reason:
            'Assistive activation must focus the operation so Escape works before a canvas click');
    semantics.dispose();
    await tester.tap(find.byKey(const ValueKey('blueprint-start-order')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final operationalEditor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(operationalEditor.viewSelection, {id},
        reason: 'Order mode inherits the current seat selection');
    expect(
        find.textContaining(BlueprintStrings.selectedCount(1)), findsOneWidget);
    final operationPanel =
        find.byKey(const ValueKey('blueprint-operation-panel'));
    expect(operationPanel, findsOneWidget);
    final canvasRect = tester.getRect(layoutCanvas());
    final operationRect = tester.getRect(operationPanel);
    expect(operationRect.center.dx, closeTo(canvasRect.center.dx, 1));
    expect(operationRect.bottom, lessThanOrEqualTo(canvasRect.bottom));
    expect(operationRect.top, greaterThan(canvasRect.center.dy));
    expect(
        find.descendant(
            of: operationPanel, matching: find.textContaining('100')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('layout-editor-toolbar')),
            matching: find.text(BlueprintStrings.confirmOrder)),
        findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('blueprint-start-order')), findsOneWidget);
    expect(identical(editor.controller.document, draft), isTrue);
    await expectActionVisible('blueprint-start-swap');
    await tester.tap(find.byKey(const ValueKey('blueprint-start-swap')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(editor.controller.dirty, isTrue);
    expect(identical(editor.controller.document, draft), isTrue);
    await expectActionVisible('blueprint-cancel-operation');
    await tester.tap(find.byKey(const ValueKey('blueprint-cancel-operation')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const ValueKey('blueprint-start-order')), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    expect(identical(editor.controller.document, draft), isTrue);
    editor.controller.markSaved();
    await tester.pump();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        isAdmin: false,
        occasionUser: OccasionUserModel(isEditor: false, isEditorOrder: false));
    await tester.pump();
    expect(editor.controller.readOnly, isTrue);
    expect(identical(editor.controller.document, draft), isTrue);
  });
  testWidgetsWithEnvironment(() => environment,
      'canvas table selection reveals its sidebar row and seats keep their own detail',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.occasionsWrite: true,
          AuthorizationCapabilities.ordersWrite: true
        },
        isAdmin: true,
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final tables = [
      for (var i = 0; i < 18; i++)
        LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            surface: {'type': 'rect'},
            label: 'T${i + 1}',
            x: 100.0 + i % 5 * 100,
            y: 100.0 + i ~/ 5 * 100)
    ];
    final lastId = tables.last.id;
    final seatId = newLayoutId();
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Scroll fixture',
            revision: 1,
            document: VenueLayoutDocument(nodes: [
              ...tables,
              LayoutNode(
                  id: seatId,
                  kind: 'seat',
                  parentId: lastId,
                  x: 80,
                  label: 'T18A'),
            ]),
            seatBindings: {
              seatId: BlueprintSeatBinding(
                  nodeId: seatId, title: 'T18A', groupNodeId: lastId)
            },
            groupProducts: {},
            areaBindings: {}),
        products: [],
        spots: []);
    final outerScroll = ScrollController(initialScrollOffset: 1280);
    addTearDown(outerScroll.dispose);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          controller: outerScroll,
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            const SizedBox(width: 1280),
            SizedBox(
                width: 1280,
                child: BlueprintLayoutHost(
                    source: source, reload: () async => source)),
          ]),
        ))));
    await tester.pumpAndSettle();
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    final row = find.byKey(ValueKey('commercial-table-$lastId'));
    final scroll = find.descendant(
        of: find.byKey(const ValueKey('blueprint-reservations-panel')),
        matching: find.byType(SingleChildScrollView));
    expect(tester.getRect(row).top, greaterThan(tester.getRect(scroll).bottom));
    expect(find.descendant(of: row, matching: find.byType(IconButton)),
        findsNothing);
    expect(editor.viewSelectionTarget!(seatId), seatId);
    final pageOrigin = tester.getTopLeft(find.byType(BlueprintLayoutHost));
    await tester
        .tapAt(layoutPoint(tester, Offset(tables.last.x, tables.last.y)));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getTopLeft(find.byType(BlueprintLayoutHost)), pageOrigin,
          reason:
              'Revealing a sidebar row must not scroll the parent tab page');
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(scroll).contains(tester.getCenter(row)), isTrue);
    expect(tester.widget<ListTile>(row).selected, isTrue);
    expect(tester.getRect(row).right,
        lessThan(tester.getRect(layoutCanvas()).left + 1));
    expect(
        tester
            .getRect(find.byKey(const ValueKey('commercial-detail-panel')))
            .left,
        greaterThan(tester.getRect(layoutCanvas()).left));
    expect(
        find.byKey(const ValueKey('commercial-detail-panel')), findsOneWidget,
        reason: 'Canvas table clicks reveal the table and open its detail');
    expect(find.byKey(const ValueKey('blueprint-seat-legend')), findsOneWidget);
    expect(find.text('T18'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    editor.onViewSelectionChanged!({seatId});
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {seatId});
    expect(find.text(BlueprintStrings.blockSeat), findsOneWidget);
    expect(tester.widget<ListTile>(row).selected, isTrue,
        reason: 'Selecting a seat highlights its parent table');
    expect(find.text(BlueprintStrings.blockSeatHint), findsNothing);
    expect(find.text(BlueprintStrings.legendBlackArea), findsNothing);
    expect(
        find.byKey(const ValueKey('commercial-detail-back')), findsOneWidget);
    final viewEditor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(viewEditor.onEditRequested, isNotNull);
    viewEditor.onEditRequested!({seatId});
    await tester.pumpAndSettle();
    final editingEditor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(editingEditor.interactionEnabled, isTrue);
    expect(find.byKey(const ValueKey('blueprint-seat-legend')), findsNothing);
    expect(editingEditor.controller.selection, {seatId});
    expect(editingEditor.onEditRequested, isNull);
    final beforeHelp = editingEditor.controller.document.toJson();
    await tester.tap(find.byKey(const ValueKey('blueprint-help')));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.helpTitle), findsWidgets);
    expect(find.text(BlueprintStrings.helpAltClick), findsOneWidget);
    expect(find.text('Ctrl / ⌘ + Z'), findsOneWidget);
    expect(find.text(BlueprintStrings.helpEnterEditKeys), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl / ⌘ + Z'), findsNothing);
    expect(editingEditor.controller.document.toJson(), beforeHelp);
  });
  testWidgetsWithEnvironment(() => environment,
      'empty blueprint chooses a template and stays in explicit editing after creation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.occasionsWrite: true,
          AuthorizationCapabilities.ordersWrite: true
        },
        isAdmin: true,
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
      blueprintId: 1,
      occasionId: 1,
      title: 'New plan',
      revision: 1,
      document: VenueLayoutDocument.empty(),
      seatBindings: const {},
    ));
    source.layoutResources =
        blueprintPreparedResourcesFixture(source.layoutSnapshot!.document);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    final template = find
        .descendant(
            of: find.byType(Dialog), matching: find.byType(OutlinedButton))
        .at(1);
    await tester.tap(template);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    expect(editor.controller.document.nodes, isNotEmpty);
    expect(editor.interactionEnabled, isTrue);
    expect(find.byType(EditorActionBar), findsOneWidget);
    editor.controller.markSaved();
    await tester.pump();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'wizard geometry save keeps a failed draft repairable and suppresses duplicates',
      (tester) async {
    var saves = 0;
    final pending = Completer<void>();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutDemo(
          // Existing draft: an empty document intentionally opens the template
          // gallery, whose modal barrier is unrelated to save/retry behavior.
          initialDocument: VenueLayoutDocument(nodes: [
            LayoutNode(
                id: '10000000-0000-4000-8000-000000000099', kind: 'group'),
          ]),
          initialResources: const {
            'protocol': 2,
            'fontFamilies': {},
            'textLayouts': {},
            'assets': {}
          },
          initiallyUnsaved: true,
          onSave: (_) {
            saves++;
            return saves == 1 ? pending.future : Future.value();
          },
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, CommonStrings.save));
    await tester.pump();
    expect(saves, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('draft_save_failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('draft_save_failed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, CommonStrings.save));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, CommonStrings.save))
            .onPressed,
        isNull);
  });

  testWidgetsWithEnvironment(() => environment,
      'wizard returns only after confirmed save and accepted geometry baseline',
      (tester) async {
    var completed = 0;
    var saves = 0;
    final pending = Completer<void>();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutDemo(
          initialDocument: VenueLayoutDocument(nodes: [
            LayoutNode(
                id: '10000000-0000-4000-8000-000000000099', kind: 'group')
          ]),
          initialResources: const {
            'protocol': 2,
            'fontFamilies': {},
            'textLayouts': {},
            'assets': {}
          },
          initiallyUnsaved: true,
          onSaved: () => completed++,
          onSave: (_) {
            saves++;
            return saves == 1 ? pending.future : Future.value();
          },
        )));
    await tester.pumpAndSettle();
    final save = find.byType(FilledButton).last;
    await tester.tap(save);
    await tester.pump();
    expect(completed, 0);
    pending.completeError(StateError('draft_save_failed'));
    await tester.pumpAndSettle();
    expect(completed, 0);
    expect(find.textContaining('draft_save_failed'), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .controller
            .dirty,
        isFalse);
    expect(find.byType(EditorActionBar), findsNothing);
  });

  testWidgetsWithEnvironment(() => environment,
      'empty catalog cannot invent a product template or call the writer',
      (tester) async {
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SelectProductDialog.catalog(
                    products: const [],
                    onProductSaved: (_) => fail(
                        'No product can be created without a template')))));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(ElevatedButton, BlueprintStrings.createProduct));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.toastNoTemplateProduct), findsOneWidget);
    expect(find.byType(EditProductDialog), findsNothing);
  });
  testWidgetsWithEnvironment(() => environment,
      'unbound standing offers sold table products and keeps its configured capacity',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalRights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
            id: 1,
            link: 'standing-fixture',
            isOpen: false,
            isHidden: true,
            isPromoted: false),
        capabilities: {
          AuthorizationCapabilities.occasionsWrite: true,
          AuthorizationCapabilities.ordersWrite: true
        },
        isAdmin: true,
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: true));
    addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = originalRights);
    const id = '10000000-0000-4000-8000-000000000020';
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Hall',
            revision: 1,
            document: VenueLayoutDocument(nodes: [
              LayoutNode(
                  id: id,
                  kind: 'capacityArea',
                  label: 'Standing',
                  x: 800,
                  y: 400,
                  width: 480,
                  height: 240,
                  properties: {'capacity': 100})
            ])));
    source.layoutResources =
        blueprintPreparedResourcesFixture(source.layoutSnapshot!.document);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source,
                reload: () async => source,
                loadTextResources: () => BlueprintTextResources.load(1,
                    service: TicketLayoutService(
                        transport: blueprintNativeFontReplyFixture)))));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('commercial-area-$id')));
    await tester.pump();
    expect(
        find.text('${BlueprintStrings.standingCapacity}: 100'), findsOneWidget);
    expect(find.text(BlueprintStrings.standingRequiresProduct), findsOneWidget);
    expect(
        find.text(BlueprintStrings.standingAvailability(0, 100)), findsNothing);
    pickerResponse = (request) {
      expect(request.url.path, endsWith('/rpc/get_product_catalog'));
      return http.Response(
          jsonEncode({
            'catalog': {
              'server_time': '2026-10-21T10:00:00Z',
              'product_types': [
                {'id': 2, 'title': 'Admission', 'type': 'spot'},
                {'id': 3, 'title': 'Extras', 'type': 'other'}
              ],
              'products': [
                {
                  'id': 9,
                  'title': 'Standing ticket',
                  'price': 80,
                  'currency_code': 'CZK',
                  'product_type': 2,
                  'ordered_count': 1
                },
                {
                  'id': 10,
                  'title': 'Table ticket',
                  'price': 500,
                  'currency_code': 'CZK',
                  'product_type': 2,
                  'ordered_count': 4
                },
                {
                  'id': 11,
                  'title': 'Non-admission product',
                  'price': 50,
                  'product_type': 3
                }
              ],
              'inventory_pools': [
                {
                  'id': 5,
                  'occasion': 1,
                  'title': 'Standing',
                  'sellable_capacity': 25
                }
              ],
              'inventory_contexts': [
                {'id': 6, 'inventory_pool': 5, 'title': 'Admission'}
              ],
              'product_inventory_contexts': [
                {'product': 9, 'inventory_context': 6, 'quantity': 1}
              ],
              'forms': [],
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    };
    await tester.tap(find.byKey(const ValueKey('assign-standing-product')));
    await tester.pumpAndSettle();
    expect(find.byType(BlueprintStandingSetupDialog), findsOneWidget);
    expect(find.byType(BlueprintProductOptions), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Table ticket'), findsOneWidget);
    expect(find.text('Non-admission product'), findsNothing);
    expect(find.text(BlueprintStrings.noSpotProducts), findsNothing);
    await tester
        .tap(find.widgetWithText(TextButton, BlueprintStrings.createProduct));
    await tester.pumpAndSettle();
    expect(find.byType(EditProductDialog), findsOneWidget);
    expect(find.text(BlueprintStrings.standingNoAdmissionType), findsNothing);
    await tester.tap(find.descendant(
        of: find.byType(EditProductDialog),
        matching: find.widgetWithText(TextButton, CommonStrings.storno)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Table ticket'));
    await tester.pump();
    final setupCapacity = find.descendant(
        of: find.byType(BlueprintStandingSetupDialog),
        matching: find.byType(TextField));
    expect(tester.widget<TextField>(setupCapacity).controller!.text, '100');
    expect(tester.widget<TextField>(setupCapacity).enabled, isTrue);
    await tester.tap(find.widgetWithText(ListTile, 'Standing ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(BlueprintStandingSetupDialog),
        matching: find.widgetWithText(
            FilledButton, BlueprintStrings.assignStandingProduct)));
    await tester.pumpAndSettle();
    expect(find.byType(BlueprintStandingSetupDialog), findsNothing);
    expect(find.byKey(const ValueKey('assign-standing-product')), findsNothing);
    expect(find.byType(BlueprintProductDetail), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(BlueprintProductDetail),
            matching: find.textContaining('Standing ticket (')),
        findsOneWidget);
    final capacityField = tester.widget<TextField>(
        find.byKey(const ValueKey('standing-capacity-field')));
    expect(capacityField.controller!.text, '25');
    // No blueprint write is sent until the user explicitly saves the draft.
    expect(source.layoutSnapshot!.areaBindings, isEmpty);
  });
}

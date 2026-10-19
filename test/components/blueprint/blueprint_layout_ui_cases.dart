import 'dart:ui' show SemanticsAction;
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_demo.dart';
import 'dart:async';
import '../../support/fixtures/root_supabase_fixture.dart';
import 'package:flutter/services.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
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
import 'package:fstapp/components/blueprint/views/blueprint_create_order_dialog.dart';
import 'package:fstapp/components/blueprint/views/blueprint_product_dialogs.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

late WidgetEnvironmentFixture environment;
void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  setUpAll(() async {
    backend = await RootSupabaseFixture.open(
        (request) => throw StateError('Unexpected UI fixture request'));
  });
  tearDownAll(() => backend.dispose());
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
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
          selectedSpotIds: const [71],
          analyze: (_) async {
            if (++analyses == 1) throw StateError('offline');
            return {
              'total_price': 100,
              'currency': 'CZK',
              'conflicts': [],
              'new_order_items': [
                {
                  'spot_id': 71,
                  'spot_title': 'A1',
                  'product_title': 'Standard',
                  'price': 100
                }
              ]
            };
          },
          submit: (_, __) {
            submissions++;
            return pending.future;
          },
        ))));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.analysisFailed), findsOneWidget);
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();
    expect(analyses, 2);
    await tester.enterText(find.byType(TextFormField), 'local@example.test');
    await tester.tap(
        find.widgetWithText(ElevatedButton, BlueprintStrings.confirmOrder));
    await tester.pump();
    expect(submissions, 1);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse);
    pending.completeError(StateError('reservation changed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reservation changed'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
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
      'blueprint inspector renames native table and commercial group together',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rights = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final group = LayoutNode(id: newLayoutId(), kind: 'group', label: 'S7');
    final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        parentId: group.id,
        x: 400,
        y: 400,
        width: 200,
        height: 100,
        label: 'S7');
    final original = VenueLayoutDocument(nodes: [group, table]);
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'Rename',
            revision: 1,
            document: original,
            seatBindings: {},
            groupProducts: {group.id: 1}));
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pumpAndSettle();
    final select =
        tester.getRect(find.byKey(const ValueKey('layout-tool-Select')));
    final pan = tester.getRect(find.byKey(const ValueKey('layout-tool-Pan')));
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('layout-tool-Select'))),
        select);
    expect(tester.getRect(find.byKey(const ValueKey('layout-tool-Pan'))), pan);
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    // The physical tabletop and its wrapper must use the same business rename.
    editor.controller.select({table.id});
    await tester.pumpAndSettle();
    final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Name');
    await tester.enterText(name, '  Front table  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.controller.document.nodes.map((n) => n.label),
        everyElement('Front table'));
    await tester.enterText(name, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
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
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        isAdmin: true, occasionUser: OccasionUserModel(isEditor: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 400,
        width: 200,
        height: 100,
        label: 'S7',
        properties: {'bold': true});
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
            blueprintId: 1,
            occasionId: 1,
            title: 'History',
            revision: 1,
            document: VenueLayoutDocument(nodes: [table]),
            seatBindings: {},
            groupProducts: {}));
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pumpAndSettle();
    final editor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    editor.controller.select({table.id});
    await tester.pumpAndSettle();
    final hostFocus = tester
        .widgetList<Focus>(find.byType(Focus))
        .singleWhere(
            (focus) => focus.focusNode?.debugLabel == 'Blueprint host actions')
        .focusNode!;
    expect(hostFocus.hasPrimaryFocus, isTrue);
    final bold = find.widgetWithIcon(IconButton, Icons.format_bold);
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
        editor.controller.document.nodes.single.properties['bold'] == true;
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
    await tester.tap(find.byTooltip(BlueprintStrings.background));
    await tester.pumpAndSettle();
    await shortcut();
    expect(isBold(), isFalse, reason: 'An open modal owns its keyboard scope');
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('blueprint-background-picker')),
        matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pumpAndSettle();
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
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pumpAndSettle();
    void expectActionVisible(String key) {
      final action = find.byKey(ValueKey(key));
      expect(action.hitTestable(), findsOneWidget);
      final badge = find.byType(EditorActionBar);
      if (badge.evaluate().isNotEmpty) {
        expect(tester.getRect(action).right,
            lessThanOrEqualTo(tester.getRect(badge).left));
      }
    }

    expectActionVisible('blueprint-start-order');
    expectActionVisible('blueprint-start-swap');
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
    expect(find.text(BlueprintStrings.selectTableOrSeat), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.table_restaurant_outlined), findsNWidgets(2));
    final canvasState = tester.state(find.byType(LayoutSceneSurface));
    final originalDocument = initialEditor.controller.document;
    final groupRow = find.byKey(const ValueKey(
        'commercial-table-10000000-0000-4000-8000-000000000002'));
    final secondRow = find.byKey(const ValueKey(
        'commercial-table-10000000-0000-4000-8000-000000000010'));
    final areaRow = find.byKey(
        const ValueKey('commercial-area-10000000-0000-4000-8000-000000000020'));
    expect(tester.getTopLeft(areaRow).dy,
        lessThan(tester.getTopLeft(groupRow).dy));
    await tester.tap(areaRow);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('commercial-detail-dialog')), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('commercial-area-product')));
    await tester.tap(find.byKey(const ValueKey('commercial-area-product')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditProductDialog>(find.byType(EditProductDialog))
            .product
            .id,
        1);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.ensureVisible(groupRow);
    await tester.tap(groupRow);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('commercial-detail-dialog')), findsOneWidget);
    expect(find.text(BlueprintStrings.groupDefaultProduct), findsOneWidget);
    expect(find.text(BlueprintStrings.statusUniform), findsOneWidget);
    expect(find.text(BlueprintStrings.uniformViewHelp), findsOneWidget);
    expect(find.byKey(ValueKey('commercial-seat-$id')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('commercial-individual-seats')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.event_seat), findsOneWidget);
    final seatRow = find.byKey(ValueKey('commercial-seat-$id'));
    await tester
        .tap(find.descendant(of: seatRow, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(find.byType(SelectProductDialog), findsOneWidget);
    expect(
        tester
            .widget<SelectProductDialog>(find.byType(SelectProductDialog))
            .currentProductId,
        1);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pumpAndSettle();
    await tester.tap(seatRow);
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.selectProduct), findsOneWidget);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {id});
    await tester.tap(find.byKey(const ValueKey('commercial-detail-back')));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.groupDefaultProduct), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.ensureVisible(secondRow);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(secondRow);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('commercial-detail-dialog')), findsNothing);
    expect(initialEditor.controller.selection, isEmpty);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .viewSelection,
        {
          '10000000-0000-4000-8000-000000000002',
          '10000000-0000-4000-8000-000000000010'
        });
    await tester
        .ensureVisible(find.byKey(const ValueKey('commercial-bulk-product')));
    await tester.tap(find.byKey(const ValueKey('commercial-bulk-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Premium'));
    await tester.pumpAndSettle();
    expect(initialEditor.controller.document, same(originalDocument));
    expect(initialEditor.controller.dirty, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('commercial-undo')));
    await tester.tap(find.byKey(const ValueKey('commercial-undo')));
    await tester.pumpAndSettle();
    expect(initialEditor.controller.dirty, isFalse);
    tester
        .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
        .onViewSelectionChanged!({id});
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.selectProduct), findsOneWidget);
    expect(initialEditor.controller.selection, isEmpty);
    expect(
        tester
            .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
            .onDragStart,
        isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    final toolbar = find.byKey(const ValueKey('layout-editor-toolbar'));
    expect(toolbar, findsOneWidget);
    expect(tester.getSize(toolbar).height, lessThanOrEqualTo(56));
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
    await tester.tap(find.byTooltip(BlueprintStrings.background));
    await tester.pump(const Duration(milliseconds: 350));
    final backgroundDialog =
        find.byKey(const ValueKey('blueprint-background-picker'));
    expect(backgroundDialog, findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'Choosing a background is not an upload');
    await tester.tap(find.descendant(
        of: backgroundDialog, matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();

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
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(LayoutSceneSurface)), same(canvasState));
    expect(find.byType(EditorActionBar), findsOneWidget);
    expect(
        tester.widget<EditorActionBar>(find.byType(EditorActionBar)).hasChanges,
        isTrue);
    expectActionVisible('blueprint-start-order');
    expectActionVisible('blueprint-start-swap');
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
    await tester.pumpAndSettle();
    final operationalEditor =
        tester.widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor));
    operationalEditor.onNodeActivated!(id);
    await tester.pump();
    expect(find.text(BlueprintStrings.selectedCount(1)), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('blueprint-start-order')), findsOneWidget);
    expect(identical(editor.controller.document, draft), isTrue);
    expectActionVisible('blueprint-start-swap');
    await tester.tap(find.byKey(const ValueKey('blueprint-start-swap')));
    await tester.pumpAndSettle();
    expect(find.text(BlueprintStrings.selectedCount(0)), findsOneWidget);
    expect(editor.controller.dirty, isTrue);
    expect(identical(editor.controller.document, draft), isTrue);
    expectActionVisible('blueprint-cancel-operation');
    await tester.tap(find.byKey(const ValueKey('blueprint-cancel-operation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('blueprint-start-order')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('blueprint-edit-mode')));
    await tester.pumpAndSettle();
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
        isAdmin: true,
        occasionUser: OccasionUserModel(isEditor: true, isEditorOrder: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = rights);
    final tables = [
      for (var i = 0; i < 18; i++)
        LayoutNode(
            id: newLayoutId(),
            kind: 'table',
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
    tester
        .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
        .onTap!(Offset(tables.last.x, tables.last.y));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getTopLeft(find.byType(BlueprintLayoutHost)), pageOrigin,
          reason:
              'Revealing a sidebar row must not scroll the parent tab page');
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(scroll).contains(tester.getCenter(row)), isTrue);
    expect(tester.widget<ListTile>(row).selected, isTrue);
    expect(
        find.byKey(const ValueKey('commercial-detail-dialog')), findsOneWidget,
        reason: 'Canvas table clicks reveal the table and open its detail');
    expect(find.text('${BlueprintStrings.manageGroupProducts}: T18'),
        findsOneWidget);
    final detailRoute = ModalRoute.of(tester
        .element(find.byKey(const ValueKey('commercial-detail-dialog'))))!;
    expect(detailRoute.transitionDuration, Duration.zero,
        reason:
            'Opening a table detail must not animate like a page transition');

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
    expect(find.text(BlueprintStrings.blockSeatHint), findsOneWidget);
    expect(find.text(BlueprintStrings.legendBlackArea), findsNothing);
    expect(
        find.byKey(const ValueKey('commercial-detail-back')), findsOneWidget);
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
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: BlueprintLayoutHost(
                source: source, reload: () async => source)));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
        tester
            .widget<VenueLayoutEditor>(find.byType(VenueLayoutEditor))
            .interactionEnabled,
        isTrue);
    final template = find
        .descendant(
            of: find.byType(Dialog), matching: find.byType(OutlinedButton))
        .first;
    await tester.tap(template);
    await tester.pumpAndSettle();
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
          initialResources: const {'protocol': 1, 'fonts': {}, 'assets': {}},
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
}

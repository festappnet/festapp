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
              label: 'Group 10'),
          LayoutNode(
              id: '10000000-0000-4000-8000-000000000002',
              kind: 'group',
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
        groupProducts: {
          '10000000-0000-4000-8000-000000000002': 1
        });
    final source = BlueprintModel(layoutSnapshot: snapshot, products: [
      ProductModel(
          id: 1,
          title: 'Standard',
          price: 100,
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
      final badge = find.byKey(const ValueKey('blueprint-unsaved-plan'));
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
    expect(find.byType(EditorActionBar), findsNothing);
    expect(find.byKey(const ValueKey('layout-palette')), findsNothing);
    final canvasState = tester.state(find.byType(LayoutSceneSurface));
    initialEditor.controller.select({id});
    await tester.pump();
    expect(find.text(BlueprintStrings.selectProduct), findsNothing);
    expect(
        tester
            .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
            .onDragStart,
        isNull);
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
    final chooser = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(chooser.items!.map((item) => (item.child as Text).data),
        ['Group 2', 'Group 10']);
    chooser.onChanged!('10000000-0000-4000-8000-000000000002');
    await tester.pump();
    expect(
        editor.controller.selection, {'10000000-0000-4000-8000-000000000002'});
    expect(editor.controller.dirty, isFalse);
    editor.controller.select({'10000000-0000-4000-8000-000000000003'});
    await tester.pump();
    expect(find.text(BlueprintStrings.seatCount(1)), findsOneWidget);
    expect(find.textContaining('${BlueprintStrings.groupDefault}: Standard'),
        findsOneWidget);
    editor.controller.beginGesture();
    editor.controller.apply(editor.controller.document.copyWith(
        canvas: {...editor.controller.document.canvas, 'width': 2600}));
    await tester.pump();
    editor.controller.commitGesture();
    final draft = editor.controller.document;
    await tester.tap(find.byKey(const ValueKey('blueprint-reservations-mode')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(LayoutSceneSurface)), same(canvasState));
    expect(find.byType(EditorActionBar), findsNothing);
    expect(
        find.byKey(const ValueKey('blueprint-unsaved-plan')), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('blueprint-unsaved-plan')));
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

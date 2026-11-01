import 'package:fstapp/components/blueprint/blueprint_font_selection.dart';
import '../../support/fixtures/blueprint_font_registry_fixture.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_state.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/forms/form_session.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/field_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import '../../../automation/blueprint-cutover/legacy_converter.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_controller.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_saver.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/forms/form_commands.dart';
import 'package:fstapp/components/forms/supabase_form_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

const node = '10000000-0000-4000-8000-000000000001';
const group = '10000000-0000-4000-8000-000000000002';
BlueprintLayoutSnapshot snapshot() => BlueprintLayoutSnapshot(
        blueprintId: 4,
        occasionId: 8,
        title: 'Hall',
        revision: 2,
        document: VenueLayoutDocument(nodes: [
          LayoutNode(id: group, kind: 'group'),
          LayoutNode(id: node, kind: 'seat', x: 100, y: 100, label: 'A')
        ]),
        seatBindings: {
          node: const BlueprintSeatBinding(
              nodeId: node,
              spotId: 11,
              productId: 1,
              groupNodeId: group,
              title: 'A')
        },
        groupProducts: {
          group: 1
        });

class Commands implements FormCommands {
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;
  Commands(this.handler);
  @override
  Future<Map<String, dynamic>> saveBlueprint(Map<String, dynamic> value) =>
      handler(value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> accepted(Map<String, dynamic> input) => {
      'code': 200,
      'blueprint_id': 4,
      'layout_revision': 3,
      'seatBindings': input['seatChanges'],
      'groupProducts': input['groupProductChanges'],
      'areaBindings': []
    };
void main() {
  test(
    'standing setup binds the authoritative prepared product as an undoable draft',
    () async {
      final id = newLayoutId();
      final otherArea = newLayoutId();
      final product = ProductModel(
        id: 9,
        occasion: 8,
        title: 'Standing',
        price: 80,
        orderedCount: 4,
        productTypeString: ProductModel.spotType,
      );
      final linked =
          product.copyWith(aggregateVersion: 1, includedInventories: [
        ProductInventoryContextModel(
            productId: 9, inventoryContextId: 6, quantity: 1),
      ]);
      final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
          blueprintId: 4,
          occasionId: 8,
          title: 'Hall',
          revision: 2,
          document: VenueLayoutDocument(
            nodes: [
              LayoutNode(
                id: id,
                kind: 'capacityArea',
                x: 400,
                y: 300,
                width: 200,
                height: 100,
                properties: {'capacity': 100},
              ),
              LayoutNode(
                  id: otherArea,
                  kind: 'capacityArea',
                  x: 700,
                  y: 300,
                  width: 200,
                  height: 100),
            ],
          ),
        ),
      );
      source.layoutResources = blueprintPreparedResourcesFixture(
        source.layoutSnapshot!.document,
      );
      Map<String, dynamic>? request;
      final c = BlueprintLayoutController(
        source: source,
        saver: BlueprintLayoutSaver(
          Commands((input) async {
            request = input;
            return {
              ...accepted(input),
              'layout_revision': 3,
              'areaBindings': input['areaBindingChanges'],
            };
          }),
        ),
      );
      addTearDown(c.dispose);
      expect(
        () => c.bindStandingArea(
          id,
          product,
          inventoryContextId: 6,
          capacity: 25,
        ),
        throwsStateError,
      );
      expect(
        () => c.bindStandingArea(
          id,
          linked.copyWith(occasion: 99),
          inventoryContextId: 6,
          capacity: 25,
        ),
        throwsStateError,
      );
      c.bindStandingArea(id, linked, inventoryContextId: 6, capacity: 25);
      expect(
          () => c.bindStandingArea(otherArea, linked,
              inventoryContextId: 6, capacity: 25),
          throwsStateError);
      expect(c.isDirty, isTrue);
      expect(request, isNull);
      expect(c.areaCapacity(id), 25);
      c.layout.undo();
      expect(c.snapshot.areaBindings, isEmpty);
      c.layout.redo();
      expect(c.snapshot.areaBindings[id]!.inventoryContextId, 6);
      expect(
        () =>
            c.bindStandingArea(id, linked, inventoryContextId: 6, capacity: 25),
        throwsStateError,
      );
      await c.save();
      expect(request!['areaBindingChanges'][0]['capacity'], 25);
      expect(c.isDirty, isFalse);
      final reloaded = BlueprintLayoutController(
        saver: c.saver,
        source: BlueprintModel(
          layoutSnapshot: BlueprintLayoutSnapshot.fromJson(c.snapshot.toJson()),
          products: [linked],
          areaAvailability: {
            id: {'capacity': 25, 'available': 25},
          },
        ),
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.snapshot.areaBindings[id]!.productId, 9);
      expect(reloaded.areaCapacity(id), 25);
      reloaded.layout.readOnly = true;
      expect(() => reloaded.setAreaCapacity(id, 5), throwsStateError);
    },
  );

  test('commercial rename and seat blocking remain drafts until explicit save',
      () async {
    final base = snapshot();
    final writes = <Map<String, dynamic>>[];
    final controller = BlueprintLayoutController(
      source: BlueprintModel(layoutSnapshot: base),
      saver: BlueprintLayoutSaver(Commands((input) async {
        writes.add(input);
        return accepted(input);
      })),
    );
    addTearDown(controller.dispose);
    final oldName = base.document.nodes.firstWhere((n) => n.id == group).label;
    controller.renameCommercialNode(group, 'Draft table');
    controller.setBlocked(node, true);
    expect(writes, isEmpty);
    expect(controller.isDirty, isTrue);
    expect(
        controller.snapshot.document.nodes
            .firstWhere((n) => n.id == group)
            .label,
        'Draft table');
    expect(base.document.nodes.firstWhere((n) => n.id == group).label, oldName);
    controller.cancel();
    expect(writes, isEmpty);
    expect(controller.isDirty, isFalse);
    expect(
        controller.snapshot.document.nodes
            .firstWhere((n) => n.id == group)
            .label,
        oldName);
    expect(controller.snapshot.seatBindings[node]!.blocked, isFalse);
    controller.renameCommercialNode(group, 'Saved table');
    controller.setBlocked(node, true);
    expect(writes, isEmpty);
    await controller.save(
        preparedResources:
            blueprintPreparedResourcesFixture(controller.snapshot.document));
    expect(writes, hasLength(1));
    expect(
        (writes.single['layout']['nodes'] as List)
            .singleWhere((n) => n['id'] == group)['label'],
        'Saved table');
    expect(controller.isDirty, isFalse);
    controller.cancel();
    expect(
        controller.snapshot.document.nodes
            .firstWhere((n) => n.id == group)
            .label,
        'Saved table');
    expect(writes, hasLength(1));
  });
  test(
      'font family change drops unsupported bold italic but preserves independent fonts',
      () {
    const oldId = '10000000-0000-4000-8000-000000000010';
    const plainId = '10000000-0000-4000-8000-000000000011';
    final families = <String, dynamic>{
      oldId: {
        'faces': {'400:normal': 'old-regular', '700:italic': 'old-bold-italic'}
      },
      plainId: {
        'faces': {'400:normal': 'plain-regular'}
      }
    };
    final a = LayoutNode(id: newLayoutId(), kind: 'text', properties: const {
      'text': 'A'
    }, style: const {
      'label': {'fontFamilyId': oldId, 'weight': 700, 'italic': true}
    });
    final b = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        properties: const {'text': 'B'},
        style: a.style);
    final before = VenueLayoutDocument(nodes: [a, b]);
    final chosen = setNodeStyleLeaf(before, a.id, ['label', 'fontFamilyId'],
        value: plainId);
    final next =
        normalizeBlueprintFontSelection(before, chosen, families, nodeId: a.id);
    final label = resolveNodeAppearance(next, next.nodes.first).label;
    expect(label['weight'], 400);
    expect(label['italic'], false);
    expect(resolvedLayoutFontFace(label, families), 'plain-regular');
    expect(next.nodes.last.toJson(), b.toJson());
    final italicAvailable = <String, dynamic>{
      ...families,
      plainId: {
        'faces': {'400:normal': 'plain-regular', '400:italic': 'plain-italic'}
      }
    };
    final withItalic = normalizeBlueprintFontSelection(
        before, chosen, italicAvailable,
        nodeId: a.id);
    final italicLabel =
        resolveNodeAppearance(withItalic, withItalic.nodes.first).label;
    expect(italicLabel['weight'], 400);
    expect(italicLabel['italic'], true);
    expect(
        resolvedLayoutFontFace(italicLabel, italicAvailable), 'plain-italic');
  });
  test(
      'document font choice normalizes inherited kind faces and keeps supported bold',
      () {
    const oldId = '10000000-0000-4000-8000-000000000010';
    const plainId = '10000000-0000-4000-8000-000000000011';
    final families = <String, dynamic>{
      oldId: {
        'faces': {'400:normal': 'old-regular', '700:italic': 'old-bold-italic'}
      },
      plainId: {
        'faces': {'400:normal': 'plain-regular'}
      }
    };
    final table = LayoutNode(
        id: newLayoutId(), kind: 'table', label: 'T', x: 100, y: 100);
    final before = VenueLayoutDocument(nodes: [
      table
    ], styles: const {
      'label': {'fontFamilyId': oldId, 'weight': 700, 'italic': true},
      'kinds': {
        'table': {
          'label': {'weight': 700}
        }
      }
    });
    final chosen = setDocumentLabelLeaf(before, 'fontFamilyId', value: plainId);
    final next = normalizeBlueprintFontSelection(before, chosen, families,
        appearanceKind: 'document');
    final label = resolveNodeAppearance(next, table).label;
    expect(resolvedLayoutFontFace(label, families), 'plain-regular');
    expect((next.styles['label'] as Map)['weight'], 400);
    expect((next.styles['kinds']['table']['label'] as Map)['weight'], 400);
    final unchanged = normalizeBlueprintFontSelection(before, before, families,
        appearanceKind: 'document');
    expect(resolveNodeAppearance(unchanged, table).label['weight'], 700);
    expect(resolveNodeAppearance(unchanged, table).label['italic'], true);
  });

  test('permission loss blocks draft save and retains the confirmed layout',
      () async {
    var calls = 0;
    final controller = BlueprintLayoutController(
      source: BlueprintModel(layoutSnapshot: snapshot()),
      saver: BlueprintLayoutSaver(Commands((input) async {
        calls++;
        return accepted(input);
      })),
    );
    addTearDown(controller.dispose);
    final confirmed = controller.layout.document;
    controller.layout.readOnly = true;
    await expectLater(controller.save(), throwsStateError);
    expect(calls, 0);
    expect(controller.layout.document, same(confirmed));
    expect(controller.saver.pending, isNull);
  });
  test('public blueprint preserves authoritative reservation expiry on reopen',
      () {
    final model = BlueprintModel.fromJson({
      ...snapshot().toJson(),
      'expiresAt': '2026-10-20T11:12:13Z',
      'spots': [],
      'products': [],
    });
    expect(model.reservationExpiresAt, DateTime.utc(2026, 10, 20, 11, 12, 13));
    expect(
        model.layoutSnapshot!.document.toJson(), snapshot().document.toJson());
  });
  test('new row seats retain generated row-letter commercial titles', () {
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
          blueprintId: 1,
          occasionId: 1,
          title: 'Rows',
          revision: 1,
          document: VenueLayoutDocument.empty(),
        ),
        products: [
          ProductModel(
              id: 1,
              title: 'Seat',
              price: 100,
              productTypeString: ProductModel.spotType)
        ]);
    final c = BlueprintLayoutController(
        source: source,
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    final rows = rowLayout(rows: 2, seatsPerRow: 3);
    expect(c.layout.apply(rows, label: 'Add rows'), true);
    expect(c.snapshot.seatBindings.values.map((s) => s.title).toSet(),
        {'1A', '1B', '1C', '2A', '2B', '2C'});
    c.layout.undo();
    expect(c.snapshot.seatBindings, isEmpty);
    c.layout.redo();
    expect(c.snapshot.seatBindings.values.map((s) => s.title).toSet(),
        {'1A', '1B', '1C', '2A', '2B', '2C'});
  });

  test(
      'standing capacity is explicit undoable frozen inventory intent including zero',
      () async {
    final id = newLayoutId();
    final area =
        BlueprintAreaBinding(nodeId: id, inventoryContextId: 3, productId: 9);
    final requests = <Map<String, dynamic>>[];
    var revision = 2;
    final source = BlueprintModel(
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
            areaBindings: {id: area}),
        areaAvailability: {
          id: {'capacity': 30, 'available': 12}
        },
        products: [
          ProductModel(id: 9, title: 'Standing', price: 80)
        ]);
    source.layoutResources =
        blueprintPreparedResourcesFixture(source.layoutSnapshot!.document);
    final c = BlueprintLayoutController(
        source: source,
        saver: BlueprintLayoutSaver(Commands((input) async {
          requests.add(input);
          return {
            ...accepted(input),
            'layout_revision': ++revision,
            'areaBindings': input['areaBindingChanges']
          };
        })));
    addTearDown(c.dispose);
    expect(c.areaCapacity(id), 30);
    expect(c.isDirty, isFalse);
    c.setAreaCapacity(id, 0);
    expect(c.areaCapacity(id), 0);
    expect(c.isDirty, isTrue);
    c.layout.undo();
    expect(c.areaCapacity(id), 30);
    expect(c.isDirty, isFalse);
    c.layout.redo();
    expect(c.areaCapacity(id), 0);
    await c.save();
    expect(requests.last['areaBindingChanges'][0]['capacity'], 0);
    c.layout.undo();
    expect(c.areaCapacity(id), 30);
    await c.save();
    expect(requests.last['areaBindingChanges'][0]['capacity'], 30);
    final captured = c.snapshot, capacities = c.areaCapacities;
    c.setAreaCapacity(id, 40);
    await c.save(captured: captured, capturedAreaCapacities: capacities);
    expect(
        (requests.last['areaBindingChanges'][0] as Map).containsKey('capacity'),
        isFalse);
    expect(c.areaCapacity(id), 40);
    expect(c.isDirty, isTrue);
  });

  test(
      'new table inherits a priced product and explicit whole-table assignment replaces exceptions only in draft',
      () {
    final base = snapshot();
    var saves = 0;
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: base, products: [
          for (final id in [1, 2])
            ProductModel(
                id: id,
                title: 'P$id',
                price: id * 100.0,
                productTypeString: ProductModel.spotType)
        ]),
        saver: BlueprintLayoutSaver(Commands((input) async {
          saves++;
          return accepted(input);
        })));
    addTearDown(c.dispose);
    final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'New table',
        x: 600,
        y: 400,
        width: 220,
        height: 160,
        surface: const {'type': 'rect'});
    final a = LayoutNode(
        id: newLayoutId(), kind: 'seat', parentId: table.id, x: 0, y: -120);
    final b = LayoutNode(
        id: newLayoutId(), kind: 'seat', parentId: table.id, x: 0, y: 120);
    expect(
        c.layout.apply(c.layout.document
            .copyWith(nodes: [...c.layout.document.nodes, table, a, b])),
        isTrue);
    expect(c.snapshot.groupProducts[table.id], 1);
    expect(c.snapshot.seatBindings[a.id]!.productId, 1);
    expect(c.snapshot.seatBindings[a.id]!.productAssignmentMode, 'inherit');
    c.assignSeatProduct(a.id, 2);
    c.applyGroupProduct(table.id, 1, replaceOverrides: true);
    expect(c.snapshot.seatBindings[a.id]!.productId, 1);
    expect(c.snapshot.seatBindings[a.id]!.productAssignmentMode, 'inherit');
    expect(c.snapshot.seatBindings[b.id]!.productId, 1);
    expect(saves, 0);
    expect(c.isDirty, isTrue);
    c.layout.undo();
    expect(c.snapshot.seatBindings[a.id]!.productId, 2);
    expect(c.snapshot.seatBindings[a.id]!.productAssignmentMode, 'override');
    expect(saves, 0);
    c.assignSeatProduct(a.id, 2);
    expect(c.suggestedSeatProductId, 2);
    final beforeProtected = c.snapshot.toJson();
    c.refreshLive(BlueprintModel(
        layoutSnapshot: base,
        products: c.products.values.toList(),
        spots: [BlueprintObjectModel(id: 11, type: 'spot', state: 'ordered')]));
    expect(() => c.applyGroupProduct(group, 2, replaceOverrides: true),
        throwsStateError);
    expect(c.snapshot.toJson(), beforeProtected);
    expect(saves, 0);
  });

  test(
      'default product suggestion uses latest priced spot catalog product when no seats exist',
      () {
    final base = BlueprintLayoutSnapshot(
        blueprintId: 4,
        occasionId: 8,
        title: 'Empty',
        revision: 2,
        document: VenueLayoutDocument.empty());
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: base, products: [
          ProductModel(
              id: 1,
              title: 'Old',
              price: 100,
              productTypeString: ProductModel.spotType,
              createdAt: DateTime(2026, 1)),
          ProductModel(
              id: 2,
              title: 'New',
              price: 200,
              productTypeString: ProductModel.spotType,
              createdAt: DateTime(2026, 2)),
          ProductModel(
              id: 3,
              title: 'Food',
              price: 200,
              productTypeString: ProductModel.foodType,
              createdAt: DateTime(2026, 3)),
          ProductModel(
              id: 4,
              title: 'Unpriced',
              productTypeString: ProductModel.spotType,
              createdAt: DateTime(2026, 4)),
        ]),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    expect(c.suggestedSeatProductId, 2);
    final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 300,
        width: 220,
        height: 160,
        surface: const {'type': 'rect'});
    expect(c.layout.apply(c.layout.document.copyWith(nodes: [table])), isTrue);
    expect(c.snapshot.groupProducts[table.id], 2);
  });

  test('live occupancy rejects old business undo without popping history', () {
    final base = snapshot();
    final products = [
      for (final id in [1, 2])
        ProductModel(
            id: id,
            title: 'P$id',
            price: 100,
            productTypeString: ProductModel.spotType)
    ];
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: base, products: products),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    c.assignSeatProduct(node, 2);
    final acceptedSnapshot = c.snapshot.toJson();
    c.refreshLive(BlueprintModel(
        layoutSnapshot: base,
        products: products,
        spots: [BlueprintObjectModel(id: 11, type: 'spot', state: 'ordered')]));
    c.layout.undo();
    expect(c.snapshot.toJson(), acceptedSnapshot);
    expect(c.layout.canUndo, isTrue);
    expect(c.layout.canRedo, isFalse);
    expect(c.layout.error, 'protected_spot');
    c.refreshLive(
        BlueprintModel(layoutSnapshot: base, products: products, spots: []));
    c.layout.undo();
    expect(c.snapshot.seatBindings[node]!.productId, 1);
    expect(c.layout.canRedo, isTrue);
  });

  test(
      'explicit attach adopts target default atomically while a visual reparent preserves commercial intent',
      () {
    final secondGroup = newLayoutId(), table = newLayoutId();
    final base = snapshot().copyWith(
        document: VenueLayoutDocument(schemaVersion: 2, nodes: [
          LayoutNode(id: group, kind: 'group'),
          LayoutNode(id: secondGroup, kind: 'group'),
          LayoutNode(
              id: table,
              kind: 'table',
              parentId: secondGroup,
              x: 700,
              y: 400,
              width: 300,
              height: 180,
              surface: {'type': 'rect'}),
          LayoutNode(id: node, kind: 'seat', x: 200, y: 200, label: 'A'),
        ]),
        groupProducts: {group: 1, secondGroup: 2});
    final products = [
      for (final id in [1, 2])
        ProductModel(
            id: id,
            title: 'P$id',
            price: 100,
            productTypeString: ProductModel.spotType)
    ];
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: base, products: products),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    c.layout.updateNode(c.layout.document.nodes
        .firstWhere((n) => n.id == node)
        .copyWith(parentId: table, x: 0, y: -132));
    expect(c.layout.error, isNull);
    expect(c.snapshot.seatBindings[node]!.groupNodeId, group);
    expect(c.snapshot.seatBindings[node]!.productId, 1);
    c.layout.undo();
    expect(c.layout.attachChairToTable(node, table), isTrue,
        reason: c.layout.error);
    expect(c.snapshot.seatBindings[node]!.groupNodeId, secondGroup);
    expect(c.snapshot.seatBindings[node]!.productId, 2);
    expect(c.snapshot.seatBindings[node]!.productAssignmentMode, 'inherit');
    c.layout.undo();
    expect(c.snapshot.seatBindings[node]!.groupNodeId, group);
    expect(c.snapshot.seatBindings[node]!.productAssignmentMode, 'override');
    c.refreshLive(BlueprintModel(
        layoutSnapshot: base,
        products: products,
        spots: [BlueprintObjectModel(id: 11, type: 'spot', state: 'ordered')]));
    c.layout.redo();
    expect(c.snapshot.seatBindings[node]!.productId, 1);
    expect(c.layout.canRedo, isTrue);
    expect(c.layout.error, 'protected_spot');
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test('save highlights overlap before reporting missing products', () async {
    final other = newLayoutId();
    final base = snapshot();
    final draft = base.copyWith(
        document: base.document.copyWith(nodes: [
          ...base.document.nodes,
          LayoutNode(id: other, kind: 'seat', x: 100, y: 100),
        ]),
        seatBindings: {
          ...base.seatBindings,
          other: BlueprintSeatBinding(nodeId: other, title: 'New'),
        });
    var calls = 0;
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: draft),
        saver: BlueprintLayoutSaver(Commands((input) async {
          calls++;
          return accepted(input);
        })));
    addTearDown(c.dispose);
    await expectLater(
        c.save(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'reason', 'layout_placement_invalid')));
    expect(c.layout.placementWarningIds, containsAll([node, other]));
    expect(calls, 0);
  });

  test(
      'table defaults preserve overrides, undo atomically and protect held seats',
      () {
    final groupA = newLayoutId(),
        groupB = newLayoutId(),
        tableA = newLayoutId();
    final inheritedA = newLayoutId(),
        overrideA = newLayoutId(),
        inheritedB = newLayoutId();
    final base = BlueprintLayoutSnapshot(
        blueprintId: 4,
        occasionId: 8,
        title: 'Hall',
        revision: 2,
        document: VenueLayoutDocument(nodes: [
          LayoutNode(id: groupA, kind: 'group', label: 'A', x: 300, y: 300),
          LayoutNode(id: groupB, kind: 'group', label: 'B', x: 600, y: 300),
          LayoutNode(
              id: tableA,
              kind: 'table',
              surface: {'type': 'rect'},
              parentId: groupA,
              label: 'A'),
          LayoutNode(
              id: inheritedA, kind: 'seat', parentId: groupA, label: 'A1'),
          LayoutNode(
              id: overrideA,
              kind: 'seat',
              parentId: groupA,
              x: 60,
              label: 'A2'),
          LayoutNode(
              id: inheritedB, kind: 'seat', parentId: groupB, label: 'B1'),
        ]),
        groupProducts: {
          groupA: 1,
          groupB: 1
        },
        seatBindings: {
          inheritedA: BlueprintSeatBinding(
              nodeId: inheritedA,
              productAssignmentMode: 'inherit',
              spotId: 11,
              groupNodeId: groupA,
              productId: 1,
              title: 'A1'),
          overrideA: BlueprintSeatBinding(
              nodeId: overrideA,
              spotId: 12,
              groupNodeId: groupA,
              productId: 2,
              title: 'A2'),
          inheritedB: BlueprintSeatBinding(
              nodeId: inheritedB,
              productAssignmentMode: 'inherit',
              spotId: 13,
              groupNodeId: groupB,
              productId: 1,
              title: 'B1'),
        });
    final products = [
      for (var id = 1; id <= 3; id++)
        ProductModel(
            id: id,
            title: 'P$id',
            price: id * 100.0,
            productTypeString: ProductModel.spotType)
    ];
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: base, products: products),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    c.applyGroupsProduct({groupA, groupB}, 3);
    expect(c.snapshot.groupProducts, {groupA: 3, groupB: 3});
    expect(c.snapshot.seatBindings[inheritedA]!.productId, 3);
    expect(c.snapshot.seatBindings[inheritedB]!.productId, 3);
    expect(c.snapshot.seatBindings[overrideA]!.productId, 2);
    expect(c.layout.document, same(base.document));
    final payload = BlueprintLayoutSaveRequest(
            snapshot: c.snapshot,
            baseline: base,
            resources: blueprintPreparedResourcesFixture(c.snapshot.document))
        .toJson();
    expect((payload['groupProductChanges'] as List).length, 2);
    c.layout.undo();
    expect(c.snapshot.groupProducts, base.groupProducts);
    expect(c.snapshot.seatBindings[inheritedA]!.productId, 1);
    expect(c.isDirty, isFalse);
    c.renameCommercialNode(groupA, 'Front table');
    expect(c.layout.document.nodes.first.label, 'Front table');
    expect(c.layout.document.nodes.firstWhere((n) => n.id == tableA).label, 'A',
        reason:
            'renaming a group does not dual-write an independent object name');
    expect(c.snapshot.seatBindings[inheritedA]!.title, 'A1');
    c.layout.undo();
    c.renameCommercialNode(inheritedA, 'A-special');
    expect(c.snapshot.seatBindings[inheritedA]!.title, 'A-special');
    expect(c.snapshot.seatBindings[inheritedA]!.spotId, 11);
    c.layout.undo();
    c.refreshLive(BlueprintModel(
        layoutSnapshot: base,
        products: products,
        spots: [BlueprintObjectModel(id: 13, state: 'ordered')]));
    expect(() => c.applyGroupsProduct({groupA, groupB}, 3), throwsStateError);
    expect(c.snapshot.groupProducts, base.groupProducts);
    expect(c.snapshot.seatBindings[inheritedA]!.productId, 1);
    c.applyGroupsProduct({groupA, groupB}, 3, freeOnly: true);
    expect(c.snapshot.seatBindings[inheritedA]!.productId, 3);
    expect(c.snapshot.seatBindings[inheritedB]!.productId, 1);
    expect(c.snapshot.seatBindings[overrideA]!.productId, 2);
    expect(() => c.renameCommercialNode(inheritedB, 'Reserved rename'),
        throwsStateError);
  });
  test(
      'new native table seats retain ancestor business group and existing lettering/default/overrides',
      () {
    const added = '10000000-0000-4000-8000-000000000003';
    const table = '10000000-0000-4000-8000-000000000004';
    final source = snapshot().copyWith(
        document: VenueLayoutDocument(nodes: [
          LayoutNode(
              id: group, kind: 'group', label: 'G', width: 400, height: 400),
          LayoutNode(
              id: table,
              kind: 'table',
              surface: {'type': 'rect'},
              parentId: group,
              x: 100,
              y: 100,
              width: 200,
              height: 100,
              label: 'Editable table'),
          LayoutNode(
              id: node,
              kind: 'seat',
              parentId: table,
              x: 24,
              y: 24,
              label: 'Custom'),
        ]),
        seatBindings: {
          node: const BlueprintSeatBinding(
              nodeId: node,
              spotId: 11,
              groupNodeId: group,
              productId: 99,
              title: 'Custom')
        },
        groupProducts: {
          group: 42
        });
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: source),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(controller.dispose);
    controller.layout.apply(source.document.copyWith(nodes: [
      ...source.document.nodes,
      LayoutNode(
          id: added, kind: 'seat', parentId: table, x: 72, y: 24, label: '1')
    ]));
    expect(controller.snapshot.seatBindings[added]!.title, 'GB');
    expect(controller.snapshot.seatBindings[added]!.productId, 42);
    expect(controller.snapshot.seatBindings[added]!.groupNodeId, group);
    expect(controller.snapshot.seatBindings[node]!.title, 'Custom');
    expect(controller.snapshot.seatBindings[node]!.productId, 99);
  });
  test(
      'customer sees blocked seats like ordered seats while admin retains blocked state',
      () {
    final existing = snapshot();
    final binding = existing.seatBindings[node]!.copyWith(blocked: true);
    final controller = BlueprintLayoutController(
        source: BlueprintModel(
            layoutSnapshot: existing.copyWith(seatBindings: {node: binding})),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(controller.dispose);
    final admin = controller.adapter.publicPresentation(binding);
    final customer = controller.adapter.customerPresentation(binding);
    expect(admin['status'], 'blocked');
    expect(admin['fill'], '#000000DE');
    expect(customer['status'], 'occupied');
    expect(customer['fill'], '#0000001F');
    expect(customer['state'], 'ordered');
    expect(customer['selectable'], false);
    expect(customer['selected'], false);
  });

  test('persisted empty seats save while new unassigned seats require a choice',
      () async {
    var calls = 0;
    final existing = snapshot().copyWith(seatBindings: {
      node: snapshot().seatBindings[node]!.copyWith(clearProduct: true)
    });
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: existing),
        saver: BlueprintLayoutSaver(Commands((input) async {
          calls++;
          return accepted(input);
        })));
    addTearDown(controller.dispose);
    expect(controller.adapter.state(existing.seatBindings[node]!),
        BlueprintSeatState.empty);
    expect(
        controller.adapter
            .publicPresentation(existing.seatBindings[node]!)['selectable'],
        false);
    expect(
        controller.adapter
            .publicPresentation(existing.seatBindings[node]!)['fill'],
        '#267329FF');
    expect((await controller.save()).accepted, true);
    expect(calls, 1);
    final draft = existing.copyWith(seatBindings: {
      node: const BlueprintSeatBinding(nodeId: node, title: 'New')
    });
    final created = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: draft),
        saver: BlueprintLayoutSaver(Commands((input) async {
          calls++;
          return accepted(input);
        })));
    addTearDown(created.dispose);
    await expectLater(created.save(), throwsStateError);
    expect(calls, 1);
    controller.refreshLive(BlueprintModel(
        spots: [BlueprintObjectModel(id: 11, type: 'spot', state: 'used')]));
    expect(controller.adapter.state(existing.seatBindings[node]!),
        BlueprintSeatState.used);
    expect(
        controller.adapter
            .publicPresentation(existing.seatBindings[node]!)['fill'],
        '#412673FF');
    expect(controller.isProtected(node), true);
  });

  test(
      'raw form suppresses addressed product controls but retains explicit standing offer',
      () {
    final definition = FormDefinition(blueprint: 4, relatedFields: [
      FormFieldDefinition(id: 99, type: 'ticket', data: {'max_tickets': 5}),
      FormFieldDefinition(id: 17, type: 'spot', isTicketField: true),
      FormFieldDefinition(
          id: 21,
          type: 'product_type',
          isTicketField: true,
          productType: ProductTypeModel(id: 2, type: 'spot', products: [
            ProductModel(id: 7, title: 'Chair', price: 100, currencyCode: 'CZK')
          ])),
      FormFieldDefinition(
          id: 23,
          type: 'product_type',
          isTicketField: true,
          productType: ProductTypeModel(id: 3, type: 'spot', products: [
            ProductModel(
                id: 9, title: 'Standing', price: 80, currencyCode: 'CZK')
          ])),
    ]);
    final key = GlobalKey<FormBuilderState>();
    final holder = FormHolder.fromDefinition(definition)
      ..controller = FormHolderController(globalKey: key);
    final tickets = holder.getTicket()!;
    expect(tickets.fields.whereType<OptionsFieldProductHolder>(), isEmpty);
    expect(tickets.offeredProductFields.map((field) => field.id), [21, 23]);
    final form = FormSession(
        form: FormBundle(definition: definition),
        formHolder: holder,
        formKey: key);
    addTearDown(form.dispose);
    form.setAreaQuantity(
        const BlueprintAreaBinding(
            nodeId: 'standing', inventoryContextId: 3, productId: 9),
        2,
        available: 5,
        product: ProductModel(
            id: 9, title: 'Standing', price: 80, currencyCode: 'CZK'));
    final payload = FormHelper.getFieldData(key, tickets) as List;
    expect(payload.length, 2);
    expect(
        (payload[0]['fields'][0]['product_type'] as FormOptionProductModel).id,
        '9');
    expect(
        tickets.tickets.first.ticketValues
            .any((field) => field.fieldType == 'spot'),
        isFalse);
    expect(tickets.tickets.first.ticketValues.single.id, 23);
    expect(form.totalPrice, 160);
  });

  test('public standing binding parses without exposing inventory context', () {
    final wire = snapshot().toJson();
    wire['areaBindings'] = [
      {'nodeId': 'public-standing', 'productId': 1}
    ];
    final publicSnapshot = BlueprintLayoutSnapshot.fromJson(wire);
    expect(publicSnapshot.areaBindings['public-standing']!.productId, 1);
    expect(publicSnapshot.areaBindings['public-standing']!.inventoryContextId,
        isNull);
    expect(
        () => BlueprintLayoutSaveRequest(
            snapshot: publicSnapshot, baseline: publicSnapshot),
        throwsStateError);
  });
  test('reader binding order cannot dirty selection or restored geometry', () {
    const other = '10000000-0000-4000-8000-000000000004';
    final base = snapshot();
    final source = base.copyWith(
        document: base.document.copyWith(nodes: [
          ...base.document.nodes,
          LayoutNode(id: other, kind: 'seat', x: 300, y: 200, label: 'B'),
        ]),
        seatBindings: {
          other: const BlueprintSeatBinding(
              nodeId: other, spotId: 12, productId: 1, title: 'B'),
          node: base.seatBindings[node]!,
        });
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: source),
        saver: BlueprintLayoutSaver(
            Commands((_) async => throw StateError('not a save'))));
    expect(controller.isDirty, false);
    controller.layout.select({node});
    expect(controller.isDirty, false);
    controller.layout.beginGesture();
    controller.layout.apply(source.document.copyWith(nodes: [
      for (final n in source.document.nodes)
        n.id == node ? n.copyWith(x: 150) : n,
    ]));
    controller.layout.commitGesture();
    expect(controller.isDirty, true);
    controller.layout.undo();
    expect(controller.isDirty, false);
    controller.dispose();
  });
  test('geometric selection does not reinterpret commercial group or override',
      () {
    const parent = '10000000-0000-4000-8000-000000000003';
    final source = snapshot().copyWith(
        document: VenueLayoutDocument(nodes: [
          LayoutNode(id: group, kind: 'group'),
          LayoutNode(id: parent, kind: 'group'),
          LayoutNode(id: node, kind: 'seat', parentId: parent, x: 100, y: 100)
        ]),
        groupProducts: {group: 1, parent: 2});
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: source),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(controller.dispose);
    controller.layout.select({node});
    expect(controller.snapshot.seatBindings[node]!.groupNodeId, group);
    expect(controller.effectiveProductId(node), 1);
    expect(controller.snapshot.seatBindings[node]!.title, 'A');
  });

  test(
      'standing uses bound blueprint catalog without duplicate form product fields',
      () {
    final key = GlobalKey<FormBuilderState>();
    final tickets =
        TicketHolder(fieldType: 'ticket', maxTickets: 5, id: 99, fields: []);
    final holder = FormHolder(fields: [tickets], isCardDesign: false)
      ..controller = FormHolderController(globalKey: key);
    final form = FormSession(
        form: FormBundle(definition: FormDefinition()),
        formHolder: holder,
        formKey: key);
    addTearDown(form.dispose);
    const area = BlueprintAreaBinding(
        nodeId: 'standing', inventoryContextId: 3, productId: 9);
    final product = ProductModel(
        id: 9, title: 'Bound standing', price: 80, currencyCode: 'CZK');
    form.setAreaQuantity(area, 2, available: 3, product: product);
    final payload = FormHelper.getFieldData(key, tickets) as List;
    expect(payload.length, 2);
    expect(
        (payload[0]['fields'][0]['product_type'] as FormOptionProductModel).id,
        '9');
    expect(form.totalPrice, 160);
    expect(
        () => form.setAreaQuantity(area, 1,
            available: 3, product: ProductModel(id: 10, price: 80)),
        throwsStateError);
    form.setAreaQuantity(area, 0, available: 0, product: null);
    expect(tickets.tickets, isEmpty);
  });

  test(
      'standing tickets use actual offered fields before mounting and survive seat refresh',
      () {
    final key = GlobalKey<FormBuilderState>();
    final option =
        FormOptionProductModel('9', 'Standing', price: 80, currencyCode: 'CZK');
    final tickets =
        TicketHolder(fieldType: 'ticket', maxTickets: 5, id: 99, fields: [
      OptionsFieldProductHolder(
          fieldType: 'product_type',
          productOptions: [option],
          selectionType: OptionsFieldProductSelectionType.selectOne,
          id: 23,
          title: 'Admission',
          isRequired: true)
    ]);
    final holder = FormHolder(fields: [tickets], isCardDesign: false)
      ..controller = FormHolderController(globalKey: key);
    final form = FormSession(
        form: FormBundle(definition: FormDefinition()),
        formHolder: holder,
        formKey: key);
    addTearDown(form.dispose);
    const area = BlueprintAreaBinding(
        nodeId: 'standing', inventoryContextId: 3, productId: 9);
    final boundProduct =
        ProductModel(id: 9, title: 'Standing', price: 80, currencyCode: 'CZK');
    form.setAreaQuantity(area, 2, available: 3, product: boundProduct);
    final payload = FormHelper.getFieldData(key, tickets) as List;
    expect(payload.length, 2);
    expect(
        (payload[0]['fields'][0]['product_type'] as FormOptionProductModel).id,
        option.id);
    expect(form.totalPrice, 160);
    form.updateSeats([]);
    expect(tickets.tickets.length, 2);
    form.setAreaQuantity(area, 1, available: 3, product: boundProduct);
    expect(form.totalPrice, 80);
    expect(
        () =>
            form.setAreaQuantity(area, 4, available: 3, product: boundProduct),
        throwsStateError);
    expect(tickets.tickets.length, 1);
  });

  test(
      'explicit legacy preparation preserves spot IDs and leaves mixed default unknown',
      () {
    final original = BlueprintModel(id: 4, occasion: 8, groups: [
      BlueprintGroupModel(id: 1, title: 'G')
    ], objects: [
      BlueprintObjectModel(
          id: 11,
          type: 'spot',
          x: 1,
          y: 1,
          groupId: 1,
          spotProduct: 1,
          state: 'available'),
      BlueprintObjectModel(
          id: 12,
          type: 'spot',
          x: 2,
          y: 1,
          groupId: 1,
          spotProduct: 2,
          state: 'ordered'),
    ]);
    final first = convertLegacyBlueprint(original,
                fontFamilies: blueprintFontRegistryFixture())
            .snapshot,
        second = convertLegacyBlueprint(original,
                fontFamilies: blueprintFontRegistryFixture())
            .snapshot;
    expect(first.seatBindings.keys, second.seatBindings.keys);
    expect(first.seatBindings.values.map((s) => s.spotId), [11, 12]);
    expect(first.groupProducts, isEmpty);
    expect(first.document.toJson().toString(), isNot(contains('spotId')));
    expect(original.objects!.last.state, 'ordered');
  });

  test(
      'ambiguous save retries exact identity and frozen payload, preserving reasons',
      () async {
    final calls = <Map<String, dynamic>>[];
    var attempt = 0;
    final commands = SupabaseFormCommands.withTransport(
        ClientCommandTransport((_, params) async {
      calls.add(params);
      if (attempt++ == 0) throw TimeoutException('lost receipt');
      final id = params['p_command_id'];
      return {
        'code': 409,
        'status': 'conflict',
        'data': {
          'code': 409,
          'reason': 'layout_revision_conflict',
          'issues': [
            {'reason': 'stale'}
          ]
        },
        'sync': {'replacements': []},
        'mutation': {
          'commandId': id,
          'receiptId': id,
          'commitId': null,
          'replayed': true,
          'occurredAt': '2026-10-19T12:00:00Z'
        }
      };
    }, maxAttempts: 1));
    final saver = BlueprintLayoutSaver(commands);
    final request =
        BlueprintLayoutSaveRequest(snapshot: snapshot(), baseline: snapshot());
    await expectLater(saver.save(request), throwsA(isA<TimeoutException>()));
    expect(saver.pending, same(request));
    await expectLater(
        saver.save(request),
        throwsA(isA<BlueprintCommandRejection>()
            .having((e) => e.reason, 'reason', 'layout_revision_conflict')));
    expect(calls[0], equals(calls[1]));
    expect(saver.pending, isNull);
  });
  test(
      'late save response keeps newer geometry and metadata undo excludes catalog/live',
      () async {
    final response = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> submitted;
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: snapshot(), products: [
          ProductModel(
              id: 1,
              title: 'A',
              price: 100,
              productTypeString: ProductModel.spotType),
          ProductModel(
              id: 2,
              title: 'B',
              price: 200,
              productTypeString: ProductModel.spotType),
        ], spots: [
          BlueprintObjectModel(id: 11, type: 'spot', state: 'available')
        ]),
        saver: BlueprintLayoutSaver(Commands((input) {
          submitted = input;
          return response.future;
        })));
    addTearDown(controller.dispose);
    controller.assignSeatProduct(node, 2);
    controller.upsertCatalogProduct(ProductModel(
        id: 2,
        title: 'Updated',
        price: 300,
        productTypeString: ProductModel.spotType));
    controller.layout.undo();
    expect(controller.effectiveProductId(node), 1);
    expect(controller.products[2]!.title, 'Updated');
    final saving = controller.save();
    controller.layout.apply(controller.layout.document.copyWith(nodes: [
      for (final n in controller.layout.document.nodes)
        n.id == node ? n.copyWith(x: 180) : n
    ]));
    response.complete(accepted(submitted));
    await saving;
    expect(controller.layout.document.nodes.firstWhere((n) => n.id == node).x,
        180);
    expect(controller.snapshot.revision, 3);
    expect(controller.isDirty, isTrue);
    controller.cancel();
    expect(controller.layout.document.nodes.firstWhere((n) => n.id == node).x,
        100);
    expect(controller.products[2]!.title, 'Updated');
    expect(controller.isDirty, isFalse);
  });
  test('geometry preview notifications stay on the canvas until commit', () {
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: snapshot()),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    var hostUpdates = 0, canvasUpdates = 0;
    c.addListener(() => hostUpdates++);
    c.layout.addListener(() => canvasUpdates++);
    c.layout.select({node});
    hostUpdates = 0;
    canvasUpdates = 0;
    c.layout.beginGesture();
    expect(
        c.layout.previewMove(c.layout.document, {node}, dx: 40, dy: 0), isTrue);
    expect(canvasUpdates, greaterThan(0));
    expect(hostUpdates, 0,
        reason:
            'Pure geometry must not rebuild all commercial host controls on each pointer move');
    expect(c.snapshot.seatBindings[node]!.spotId, 11);
    c.layout.commitGesture();
    expect(hostUpdates, 1);
    expect(c.isDirty, isTrue);
  });
  test('geometry previews retain commercial binding identities', () {
    final c = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: snapshot()),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    final binding = c.snapshot.seatBindings[node]!;
    final document = c.layout.document;
    expect(
        c.layout.apply(document.copyWith(nodes: [
          for (final n in document.nodes) n.id == node ? n.copyWith(x: 180) : n
        ])),
        isTrue);
    expect(identical(c.snapshot.seatBindings[node], binding), isTrue);
    expect(c.snapshot.seatBindings[node]!.spotId, 11);
    expect(
        c.layout.apply(c.layout.document.copyWith(nodes: [
          for (final n in c.layout.document.nodes)
            n.id == node ? n.copyWith(label: 'Renamed') : n
        ])),
        isTrue);
    expect(c.snapshot.seatBindings[node]!.title, 'Renamed');
  });
  test('bulk blocking is atomic undoable and rejects a protected sofa member',
      () {
    final doc = couchLayout(count: 2);
    final root = doc.nodes.firstWhere(isCouchNode);
    final seats = doc.nodes.where((n) => n.kind == 'seat').toList();
    final source = BlueprintModel(
        layoutSnapshot: BlueprintLayoutSnapshot(
          blueprintId: 1,
          occasionId: 8,
          title: 'Hall',
          revision: 2,
          document: doc,
          seatBindings: {
            for (var i = 0; i < seats.length; i++)
              seats[i].id: BlueprintSeatBinding(
                  nodeId: seats[i].id,
                  spotId: 11 + i,
                  productId: 1,
                  groupNodeId: root.id)
          },
          groupProducts: {root.id: 1},
        ),
        products: [
          ProductModel(
              id: 1,
              title: 'Seat',
              price: 100,
              productTypeString: ProductModel.spotType)
        ],
        spots: [
          BlueprintObjectModel(id: 11, state: 'available'),
          BlueprintObjectModel(id: 12, state: 'available')
        ]);
    final c = BlueprintLayoutController(
        source: source,
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(c.dispose);
    c.setBlockedForSeats({seats.first.id}, true);
    expect(c.snapshot.seatBindings.values.every((s) => s.blocked), isTrue);
    c.layout.undo();
    expect(c.snapshot.seatBindings.values.every((s) => !s.blocked), isTrue);
    expect(c.layout.canUndo, isFalse);
    c.adapter.spots[12]!.setSeatState(BlueprintSeatState.selected);
    expect(
        () => c.setBlockedForSeats({seats.first.id}, true), throwsStateError);
    expect(c.snapshot.seatBindings.values.every((s) => !s.blocked), isTrue);
  });
  test('live holds protect products while movement retains spot identity', () {
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: snapshot(), products: [
          ProductModel(
              id: 1,
              title: 'A',
              price: 100,
              productTypeString: ProductModel.spotType),
        ], spots: [
          BlueprintObjectModel(id: 11, type: 'spot', state: 'selected')
        ]),
        saver:
            BlueprintLayoutSaver(Commands((input) async => accepted(input))));
    addTearDown(controller.dispose);
    expect(() => controller.assignSeatProduct(node, 1), throwsStateError);
    controller.applyGroupProduct(group, 1);
    expect(controller.snapshot.seatBindings[node]!.productAssignmentMode,
        'override');
    expect(controller.snapshot.seatBindings[node]!.productId, 1);
    controller.layout.apply(controller.layout.document.copyWith(nodes: [
      for (final n in controller.layout.document.nodes)
        n.id == node ? n.copyWith(x: 180) : n
    ]));
    expect(controller.snapshot.seatBindings[node]!.spotId, 11);
    expect(
        controller.layout.apply(controller.layout.document.copyWith(nodes: [])),
        isFalse);
  });
}

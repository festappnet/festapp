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
import 'package:fstapp/components/blueprint/blueprint_legacy_converter.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  test('new native table seats retain ancestor business group and existing lettering/default/overrides', () {
    const added='10000000-0000-4000-8000-000000000003';
    const table='10000000-0000-4000-8000-000000000004';
    final source=snapshot().copyWith(document:VenueLayoutDocument(nodes:[
      LayoutNode(id:group,kind:'group',label:'G',width:400,height:400),
      LayoutNode(id:table,kind:'table',parentId:group,x:100,y:100,width:200,height:100,label:'Editable table'),
      LayoutNode(id:node,kind:'seat',parentId:table,x:24,y:24,label:'Custom'),
    ]),seatBindings:{node:const BlueprintSeatBinding(nodeId:node,spotId:11,
      groupNodeId:group,productId:99,title:'Custom')},groupProducts:{group:42});
    final controller=BlueprintLayoutController(source:BlueprintModel(layoutSnapshot:source),
      saver:BlueprintLayoutSaver(Commands((input)async=>accepted(input))));
    addTearDown(controller.dispose);
    controller.layout.apply(source.document.copyWith(nodes:[...source.document.nodes,
      LayoutNode(id:added,kind:'seat',parentId:table,x:72,y:24,label:'1')]));
    expect(controller.snapshot.seatBindings[added]!.title,'GB');
    expect(controller.snapshot.seatBindings[added]!.productId,42);
    expect(controller.snapshot.seatBindings[added]!.groupNodeId,group);
    expect(controller.snapshot.seatBindings[node]!.title,'Custom');
    expect(controller.snapshot.seatBindings[node]!.productId,99);
  });
  test('persisted empty seats save while new unassigned seats require a choice', () async {
    var calls=0;
    final existing=snapshot().copyWith(seatBindings:{node:snapshot().seatBindings[node]!.copyWith(clearProduct:true)});
    final controller=BlueprintLayoutController(source:BlueprintModel(layoutSnapshot:existing),saver:BlueprintLayoutSaver(Commands((input)async{calls++;return accepted(input);})));
    addTearDown(controller.dispose);
    expect(controller.adapter.state(existing.seatBindings[node]!),BlueprintSeatState.empty);
    expect(controller.adapter.publicPresentation(existing.seatBindings[node]!)['selectable'],false);
    expect(controller.adapter.publicPresentation(existing.seatBindings[node]!)['fill'],'#267329FF');
    expect((await controller.save()).accepted,true);
    expect(calls,1);
    final draft=existing.copyWith(seatBindings:{node:const BlueprintSeatBinding(nodeId:node,title:'New')});
    final created=BlueprintLayoutController(source:BlueprintModel(layoutSnapshot:draft),saver:BlueprintLayoutSaver(Commands((input)async{calls++;return accepted(input);})));
    addTearDown(created.dispose);
    await expectLater(created.save(),throwsStateError);
    expect(calls,1);
    controller.refreshLive(BlueprintModel(spots:[BlueprintObjectModel(id:11,type:'spot',state:'used')]));
    expect(controller.adapter.state(existing.seatBindings[node]!),BlueprintSeatState.used);
    expect(controller.adapter.publicPresentation(existing.seatBindings[node]!)['fill'],'#412673FF');
    expect(controller.isProtected(node),true);
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
        available: 5);
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
    form.setAreaQuantity(area, 2, available: 3);
    final payload = FormHelper.getFieldData(key, tickets) as List;
    expect(payload.length, 2);
    expect(payload[0]['fields'][0]['product_type'], same(option));
    expect(form.totalPrice, 160);
    form.updateSeats([]);
    expect(tickets.tickets.length, 2);
    form.setAreaQuantity(area, 1, available: 3);
    expect(form.totalPrice, 80);
    expect(() => form.setAreaQuantity(area, 4, available: 3), throwsStateError);
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
    final first = convertLegacyBlueprint(original),
        second = convertLegacyBlueprint(original);
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
    controller.layout.apply(controller.layout.document.copyWith(
        nodes: [controller.layout.document.nodes.single.copyWith(x: 180)]));
    response.complete(accepted(submitted));
    await saving;
    expect(controller.layout.document.nodes.single.x, 180);
    expect(controller.snapshot.revision, 3);
    expect(controller.isDirty, isTrue);
    controller.cancel();
    expect(controller.layout.document.nodes.single.x, 100);
    expect(controller.products[2]!.title, 'Updated');
    expect(controller.isDirty, isFalse);
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
    expect(() => controller.applyGroupProduct(group, 1), throwsStateError);
    controller.layout.apply(controller.layout.document.copyWith(
        nodes: [controller.layout.document.nodes.single.copyWith(x: 180)]));
    expect(controller.snapshot.seatBindings[node]!.spotId, 11);
    expect(
        controller.layout.apply(controller.layout.document.copyWith(nodes: [])),
        isFalse);
  });
}

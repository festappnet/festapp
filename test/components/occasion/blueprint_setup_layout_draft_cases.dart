import 'dart:convert';
import 'package:fstapp/components/occasion/setup/occasion_form_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/occasion/setup/blueprint_setup_layout_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_pricing.dart';

void main() {
  test('new products keep local identities across saves and price wave edits',
      () async {
    final form = draftFormBundle({
      'fields': [
        {
          'type': 'product_type',
          'product_type_data': {
            'id': 12,
            'type': 'spot',
            'products': [
              {
                'id': 145,
                'title': 'Copied',
                'price': 200,
                'currency_code': 'EUR'
              },
              {'id': -3, 'title': 'Existing draft', 'price': 100},
              {'title': 'Student', 'price': 50, 'currency_code': ''},
            ]
          }
        },
        {
          'type': 'product_type',
          'product_type_data': {
            'type': 'product',
            'products': [
              {'title': 'New type', 'price': 10}
            ]
          }
        }
      ]
    }).form;
    final first = serializeDraftForm(form);
    expect(serializeDraftForm(form), first);
    final bundle = draftFormBundle(first);
    expect(serializeDraftForm(bundle.form), first);
    final ids = bundle.products.map((p) => p.id).toList();
    expect(ids.take(2), [145, -3]);
    expect(ids.toSet(), hasLength(4));
    expect(ids.skip(2), everyElement(isNegative));
    expect(bundle.productTypes.first.id, 12);
    expect(bundle.productTypes.last.id, isNegative);
    expect(bundle.products[2].currencyCode, 'EUR');
    expect(bundle.products.last.currencyCode, 'CZK');
    final data = <String, dynamic>{'formDraft': first};
    final actions = OccasionSetupPriceWaveDraft(data, data.addAll);
    final wave =
        await actions.create(DateTime.now().add(const Duration(days: 1)));
    await actions.saveTarget(wave, bundle.products[2], 80, true);
    expect((data['priceWaves'] as List).single['targets'], [
      {'product': ids[2], 'price': 80.0, 'is_hidden': true}
    ]);
    expect(actions.bundle().products[2].priceChanges.single.price, 80);
    final edited = jsonDecode(jsonEncode(first)) as Map<String, dynamic>;
    final products =
        edited['fields'][0]['product_type_data']['products'] as List;
    products.removeAt(2);
    products.add({'title': 'Replacement', 'price': 40});
    final replacement =
        draftFormBundle(serializeDraftForm(draftFormBundle(edited).form));
    expect(replacement.products.map((p) => p.id), isNot(contains(ids[2])));
  });
  test('normalized seat field opens form bundle without a JSON save roundtrip',
      () {
    final data = jsonDecode('''{
      "blueprintMode":"copy",
      "formDraft":{"title":"Admission","fields":[
        {"type":"ticket"},
        {"type":"spot","is_ticket_field":true,"is_hidden":true,
          "title":"Choose your seat","data":{"hint":"Hall"}}
      ]}
    }''') as Map<String, dynamic>;
    final owner = SetupBlueprintConfiguration(data);
    owner.normalize();
    final form =
        draftFormBundle(data['formDraft'] as Map<String, dynamic>).form;
    expect(form.usesSeatSelection, true);
    final field =
        form.relatedFields.singleWhere((f) => f.definition.type == 'spot');
    expect(field.definition.title, 'Choose your seat');
    expect(field.definition.data?['hint'], 'Hall');
    owner.normalize();
    expect(
        draftFormBundle(data['formDraft'] as Map<String, dynamic>)
            .form
            .usesSeatSelection,
        true);
    owner.clear();
    expect(
        draftFormBundle(data['formDraft'] as Map<String, dynamic>)
            .form
            .usesSeatSelection,
        false);
  });
  test('setup mode owns geometry and public seat selection, retaining products',
      () {
    final doc = VenueLayoutDocument(nodes: [
      LayoutNode(id: '00000000-0000-4000-8000-000000000001', kind: 'seat'),
      LayoutNode(id: '00000000-0000-4000-8000-000000000002', kind: 'shape')
    ]);
    final raw =
        BlueprintSetupLayoutDraft.empty(document: doc, resources: const {})
            .reconcile(doc, defaultProductId: 42)
            .toJson();
    final data = <String, dynamic>{
      'blueprintMode': 'Bez plánku',
      'formEnabled': true,
      'formDraft': {
        'fields': [
          {'type': 'ticket'},
          {
            'type': 'product_type',
            'product_type_data': {
              'id': 1,
              'type': 'spot',
              'products': [
                {'id': 42}
              ]
            }
          }
        ]
      }
    };
    final owner = SetupBlueprintConfiguration(data);
    owner.importPlan({'id': 7, 'title': 'Hall', 'blueprintLayoutDraft': raw});
    expect(owner.modeId, 'copy');
    expect(owner.seatCount, 1);
    expect(owner.ready, true);
    expect(
        (data['formDraft']['fields'] as List)
            .where((f) => f['type'] == 'spot')
            .single['is_hidden'],
        false);
    expect(() => owner.importPlan({'id': 8}), throwsFormatException);
    expect(data['blueprintSourceId'], 7,
        reason: 'Unsupported source preserves last valid plan');
    owner.clear();
    expect(data.containsKey('blueprintLayoutDraft'), false);
    expect((data['formDraft']['fields'] as List).length, 2);
    expect(owner.ready, true);
    owner.clear(create: true);
    expect(owner.ready, false,
        reason: 'An unfinished new plan can save but cannot finalize');
  });
  test('seat counts ignore orphan bindings, blocked seats and decoration', () {
    final doc = VenueLayoutDocument(nodes: [
      LayoutNode(id: '00000000-0000-4000-8000-000000000001', kind: 'shape')
    ]);
    final data = <String, dynamic>{
      'blueprintMode': 'copy',
      'formEnabled': true,
      'blueprintLayoutDraft': {
        'layout': doc.toJson(),
        'seatBindings': [
          {'nodeId': '00000000-0000-4000-8000-000000000001', 'productId': 42},
          {'nodeId': '00000000-0000-4000-8000-000000000002', 'productId': 42}
        ]
      }
    };
    expect(SetupBlueprintConfiguration(data).seatCount, 0);
    expect(SetupBlueprintConfiguration(data).ready, false);
  });
  test(
      'supported legacy document adapts in a private copy through canonical importer',
      () {
    final legacy = <String, dynamic>{
      'schemaVersion': 1,
      'symbolSetVersion': 1,
      'canvas': {
        'x': 0.0,
        'y': 0.0,
        'width': 1000.0,
        'height': 1000.0,
        'fill': '#FFFFFFFF'
      },
      'nodes': [
        LayoutNode(
                id: '00000000-0000-4000-8000-000000000001',
                kind: 'seat',
                label: 'A1')
            .toJson()
      ],
      'defaultTextStyle': {
        'fontId': 'fixture:sans',
        'size': 24,
        'color': '#222222FF'
      }
    };
    final plan = {
      'id': 9,
      'blueprintLayoutDraft': {
        'layout': legacy,
        'seatBindings': [
          {
            'nodeId': '00000000-0000-4000-8000-000000000001',
            'productId': 42,
            'spotId': 99
          }
        ]
      }
    };
    final adapted =
        SetupBlueprintConfiguration.adaptSource(plan, fontFamilies: {
      'family:sans': {
        'id': 'family:sans',
        'faces': {'400:normal': 'fixture:sans'}
      }
    });
    final draft =
        BlueprintSetupLayoutDraft.fromJson(adapted['blueprintLayoutDraft']);
    expect(draft.document.schemaVersion, 2);
    expect(draft.seatBindings.values.single.productId, 42);
    expect(draft.seatBindings.values.single.spotId, isNull);
    expect(legacy['schemaVersion'], 1);
  });
  test('translated and absent mode values migrate to stable IDs', () {
    expect(
        SetupBlueprintConfiguration({'blueprintMode': 'Nový'}).modeId, 'new');
    expect(SetupBlueprintConfiguration({'blueprintMode': 'Převzít'}).modeId,
        'copy');
    expect(SetupBlueprintConfiguration({'blueprintLayoutDraft': {}}).modeId,
        'copy');
  });
  test(
      'setup draft keeps explicit overrides and never persists live identities/resources',
      () {
    const group = '00000000-0000-4000-8000-000000000001';
    const seat = '00000000-0000-4000-8000-000000000002';
    const area = '00000000-0000-4000-8000-000000000003';
    final document = VenueLayoutDocument(nodes: [
      LayoutNode(id: group, kind: 'group'),
      LayoutNode(id: seat, kind: 'seat', parentId: group, label: 'Chair'),
      LayoutNode(id: area, kind: 'capacityArea', x: 300, y: 300),
    ]);
    final draft = BlueprintSetupLayoutDraft.empty(
            document: document, resources: {'fonts': {}})
        .reconcile(document, defaultProductId: 42)
        .withArea(nodeId: area, productId: 43, capacity: 5);
    expect(
        resolveNodeAppearance(draft.document,
                document.nodes.firstWhere((node) => node.id == seat))
            .label['fontFamilyId'],
        canonicalLabelDefaults['fontFamilyId']);
    expect(draft.seatBindings[seat]!.productId, 42);
    expect(draft.groupProducts[group], 42);
    final encoded = draft.toJson();
    expect(encoded.containsKey('resources'), false);
    final binding = (encoded['seatBindings'] as List).single as Map;
    expect(binding.containsKey('spotId'), false);
    binding['productId'] = 44;
    final restored = BlueprintSetupLayoutDraft.fromJson(encoded)
        .reconcile(draft.document, defaultProductId: 99);
    expect(restored.seatBindings[seat]!.productId, 44);
    expect(restored.areaBindings.single['capacity'], 5);
    expect(() => restored.withArea(nodeId: area, productId: 43, capacity: -1),
        throwsStateError);
  });
  test('new setup seat in mixed group needs an explicit group default', () {
    const group = '00000000-0000-4000-8000-000000000001';
    const first = '00000000-0000-4000-8000-000000000002';
    const second = '00000000-0000-4000-8000-000000000003';
    const added = '00000000-0000-4000-8000-000000000004';
    final document = VenueLayoutDocument(nodes: [
      LayoutNode(id: group, kind: 'group'),
      LayoutNode(id: first, kind: 'seat', parentId: group),
      LayoutNode(id: second, kind: 'seat', parentId: group)
    ]);
    final draft = BlueprintSetupLayoutDraft.fromJson({
      'layout': document.toJson(),
      'seatBindings': [
        for (final id in [first, second])
          {
            'nodeId': id,
            'groupNodeId': group,
            'productId': id == first ? 42 : 43,
            'title': '',
            'blocked': false
          }
      ],
      'groupProducts': [],
      'areaBindings': []
    });
    final next = VenueLayoutDocument.fromJson({
      ...document.toJson(),
      'nodes': [
        ...document.nodes.map((node) => node.toJson()),
        LayoutNode(id: added, kind: 'seat', parentId: group).toJson()
      ]
    });
    final updated = draft.reconcile(next, defaultProductId: 99);
    expect(updated.seatBindings[first]!.productId, 42);
    expect(updated.seatBindings[added]!.productId, isNull);
    expect(updated.groupProducts.containsKey(group), false);
    final chosen = updated.withGroupProduct(group, 99, assignNodeIds: {added});
    expect(chosen.seatBindings[added]!.productId, 99);
    expect(chosen.seatBindings[first]!.productId, 42);
    expect(chosen.groupProducts[group], 99);
  });

  test(
      'setup native table children inherit ancestor business default and preserve overrides',
      () {
    const group = '00000000-0000-4000-8000-000000000001';
    const table = '00000000-0000-4000-8000-000000000002';
    const seat = '00000000-0000-4000-8000-000000000003';
    const added = '00000000-0000-4000-8000-000000000004';
    final document = VenueLayoutDocument(nodes: [
      LayoutNode(id: group, kind: 'group'),
      LayoutNode(
          id: table, kind: 'table', surface: {'type': 'rect'}, parentId: group),
      LayoutNode(id: seat, kind: 'seat', parentId: table)
    ]);
    final draft = BlueprintSetupLayoutDraft.fromJson({
      'layout': document.toJson(),
      'seatBindings': [
        {
          'nodeId': seat,
          'groupNodeId': group,
          'productId': 99,
          'title': 'Override',
          'blocked': false
        }
      ],
      'groupProducts': [
        {'groupNodeId': group, 'productId': 42}
      ],
      'areaBindings': []
    });
    final next = document.copyWith(nodes: [
      ...document.nodes,
      LayoutNode(id: added, kind: 'seat', parentId: table)
    ]);
    final updated = draft.reconcile(next, defaultProductId: 7);
    expect(updated.seatBindings[added]!.groupNodeId, group);
    expect(updated.seatBindings[added]!.productId, 42);
    expect(updated.seatBindings[seat]!.productId, 99);
  });
}

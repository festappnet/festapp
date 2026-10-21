import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_references.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_reference_dialog.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_source_picker.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

Map<String, dynamic> candidate() => {
      'formEnabled': true,
      'formDraft': {
        'fields': [
          {'type': 'ticket'},
          {
            'type': 'product_type',
            'product_type_data': {
              'id': 20,
              'title': 'New group',
              'type': 'spot',
              'products': [
                {
                  'id': 200,
                  'title': 'New admission',
                  'price': 200,
                  'currency_code': 'CZK'
                },
              ]
            }
          },
        ]
      },
      'blueprintMode': 'Převzít',
      'blueprintLayoutDraft': {
        'layout': {
          'nodes': [
            {
              'id': 'a',
              'transform': {'x': 33, 'y': 70}
            }
          ]
        },
        'seatBindings': [
          {'nodeId': 'a', 'productId': 100}
        ],
        'groupProducts': [
          {'groupNodeId': 'group', 'productId': 100}
        ],
        'areaBindings': [
          {'nodeId': 'area', 'productId': 100, 'capacity': 7}
        ],
      },
      'ticketDraft': {
        'layout': {
          'schemaVersion': 3,
          'templates': {
            'wide': {
              'flow': ['dinner'],
              'elements': [
                {
                  'id': 'dinner',
                  'binding': 'productType',
                  'productTypeId': 10,
                  'label': 'Večeře',
                  'box': {'x': 10, 'y': 44, 'width': 80, 'height': 15},
                  'style': {'fontSize': 12}
                },
              ]
            },
          }
        }
      },
    };

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));

  test('form replacement requires explicit product and ticket-group choices',
      () {
    final data = candidate();
    final original = jsonEncode(data);
    final refs = OccasionSetupReferences(data);
    expect(refs.missingProducts, {100});
    expect(refs.missingTypes, {10});
    final next = refs.rebind(products: {100: 200}, productTypes: {10: 20});
    expect(OccasionSetupReferences(next).hasIssues, isFalse);
    for (final key in ['seatBindings', 'groupProducts', 'areaBindings']) {
      expect(next['blueprintLayoutDraft'][key][0]['productId'], 200);
    }
    expect(next['blueprintLayoutDraft']['layout'],
        data['blueprintLayoutDraft']['layout']);
    final element =
        next['ticketDraft']['layout']['templates']['wide']['elements'][0];
    expect(element['productTypeId'], 20);
    expect(element['label'], 'Večeře');
    expect(
        element['box'],
        data['ticketDraft']['layout']['templates']['wide']['elements'][0]
            ['box']);
    expect(
        next['ticketDraft']['layout']['templates']['wide']['flow'], ['dinner']);
    expect(jsonEncode(data), original);
  });
  test('dormant blueprint and ticket survive without blocking replacement', () {
    final data = candidate()..['blueprintMode'] = 'Bez plánku';
    (data['formDraft']['fields'] as List).removeAt(0);
    expect(OccasionSetupReferences(data).hasIssues, isFalse);
    final next = OccasionSetupReferences(data)
        .rebind(products: {100: 200}, productTypes: {10: 20});
    expect(next['blueprintLayoutDraft'], data['blueprintLayoutDraft']);
    expect(next['ticketDraft'], data['ticketDraft']);
    next['blueprintMode'] = 'Převzít';
    expect(OccasionSetupReferences(next).missingProducts, {100});
  });
  test('mapping cannot merge two ticket fields into the same product group',
      () {
    final data = candidate();
    (data['ticketDraft']['layout']['templates']['wide']['elements'] as List)
        .add({
      'id': 'other',
      'binding': 'productType',
      'productTypeId': 20,
      'label': 'Other'
    });
    final next = OccasionSetupReferences(data)
        .rebind(products: {100: 200}, productTypes: {10: 20});
    expect(OccasionSetupReferences(next).duplicateTypes, isTrue);
    expect(OccasionSetupReferences(next).hasIssues, isTrue);
  });
  test('unchanged valid form bindings stay valid', () {
    final data = OccasionSetupReferences(candidate())
        .rebind(products: {100: 200}, productTypes: {10: 20});
    expect(OccasionSetupReferences(data).hasIssues, isFalse);
  });

  testWidgetsWithEnvironment(() => environment,
      'equal source labels select by ID and display distinct links',
      (tester) async {
    int? selected;
    final sources = [
      for (final id in [1, 2])
        {
          'occasion': {'id': id, 'link': 'source-$id'}
        }
    ];
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OccasionSetupSourcePicker(
                    sources: sources,
                    selectedId: null,
                    label: (_) => 'Same name (21.10.2026)',
                    onChanged: (id) => selected = id))));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is RadioListTile<bool> && w.value == false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Same name (21.10.2026) · source-2').last);
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgetsWithEnvironment(
      () => environment, 'unavailable source remains identified during loading',
      (tester) async {
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OccasionSetupSourcePicker(
                    sources: const [],
                    selectedId: 7,
                    unavailableLabel: 'Saved source',
                    label: (_) => '',
                    onChanged: (_) {}))));
    expect(find.text('Saved source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgetsWithEnvironment(() => environment,
      'reference dialog blocks save until both choices are explicit',
      (tester) async {
    Map<String, dynamic>? saved;
    final data = candidate();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          saved = await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => OccasionSetupReferenceDialog(
                                  data: data, previous: data));
                        },
                        child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('seat-product-100')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New admission · 200 CZK').last);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('ticket-type-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New group').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(OccasionSetupReferences(saved!).hasIssues, isFalse);
    expect(OccasionSetupReferences(data).hasIssues, isTrue);
  });
}

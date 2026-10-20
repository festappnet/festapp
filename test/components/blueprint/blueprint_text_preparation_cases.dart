import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_text_preparation.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_controller.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_saver.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/forms/form_commands.dart';

class Commands implements FormCommands {
  Commands(this.handler);
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;
  @override
  Future<Map<String, dynamic>> saveBlueprint(Map<String, dynamic> value) =>
      handler(value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final fixture = jsonDecode(
      File('test/fixtures/blueprint/canonical-text-scene.json')
          .readAsStringSync()) as Map;
  final document = VenueLayoutDocument.fromJson(
      Map<String, dynamic>.from(fixture['document']));
  final families =
      Map<String, dynamic>.from(fixture['resources']['fontFamilies']);
  Map<String, dynamic> reply(Map<String, dynamic> batch) => {
        'protocol': 2,
        'fontFamilies': families,
        'numberSymbols': {},
        'textLayouts': {
          for (final raw in batch['requests'] as List)
            LayoutTextRequest(Map<String, dynamic>.from(raw)).id: {
              'id': LayoutTextRequest(Map<String, dynamic>.from(raw)).id,
              'descriptor': LayoutTextRequest(Map<String, dynamic>.from(raw))
                  .resourceDescriptor,
              'path': [
                ['M', 0, 0],
                ['L', 1, 1]
              ],
              'clip': raw['box'],
            }
        },
      };
  test(
      'scoped immutable families remain resolvable after current catalog discovery changes',
      () async {
    final saved = Map<String, dynamic>.from(fixture['resources'] as Map);
    var calls = 0;
    final preparation = BlueprintTextPreparation((batch) async {
      calls++;
      return reply(batch);
    });
    final ready = await preparation.prepareSnapshot(document, {}, saved);
    expect(calls, 0);
    expect(ready['fontFamilies'], families);
    final changed = document.copyWith(nodes: [
      document.nodes.first
          .copyWith(properties: {'text': 'Retained manifest text'}),
      ...document.nodes.skip(1)
    ]);
    final updated = await preparation.prepareSnapshot(changed, {}, saved);
    expect(calls, 1);
    expect(updated['fontFamilies'], families);
    expect(collectLayoutTextResourceIds(changed, updated), isNotEmpty);
    final id = families.keys.first,
        conflict = {
          ...families,
          id: {...families[id] as Map, 'family': 'Changed immutable manifest'}
        };
    await expectLater(
        preparation.prepareSnapshot(document, conflict, saved),
        throwsA(isA<LayoutTextDependencyFailure>().having(
            (error) => error.reason,
            'reason',
            'font_family_manifest_conflict')));
    expect(calls, 1);
  });
  test(
      'out-of-order full-text preparation returns ready or superseded explicitly',
      () async {
    final waits = <Completer<Map<String, dynamic>>>[],
        batches = <Map<String, dynamic>>[];
    final preparation = BlueprintTextPreparation((batch) {
      batches.add(batch);
      final c = Completer<Map<String, dynamic>>();
      waits.add(c);
      return c.future;
    });
    var current = document;
    final a = preparation.prepare(document, families, {},
        stillCurrent: () => identical(current, document));
    final changed = document.copyWith(nodes: [
      document.nodes.first.copyWith(properties: {'text': 'new text'}),
      ...document.nodes.skip(1)
    ]);
    current = changed;
    final b = preparation.prepare(changed, families, {},
        stillCurrent: () => identical(current, changed));
    waits[1].complete(reply(batches[1]));
    expect(await b, isA<BlueprintTextReady>());
    waits[0].complete(reply(batches[0]));
    expect(await a, isA<BlueprintTextSuperseded>());
    final failure = BlueprintTextPreparation(
        (_) async => throw StateError('font_unavailable'));
    expect(await failure.prepare(document, families, {}),
        isA<BlueprintTextFailed>());
  });
  test(
      'save waits for its captured document and preserves newer edits and exact retry references',
      () async {
    final wait = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> batch;
    Map<String, dynamic>? sent;
    final preparation = BlueprintTextPreparation((request) {
      batch = request;
      return wait.future;
    });
    final snapshot = BlueprintLayoutSnapshot(
        blueprintId: 1,
        occasionId: 1,
        title: 'Plan',
        revision: 1,
        document: document);
    final controller = BlueprintLayoutController(
        source: BlueprintModel(layoutSnapshot: snapshot),
        saver: BlueprintLayoutSaver(Commands((request) async {
          sent = request;
          return {
            'code': 200,
            'blueprint_id': 1,
            'layout_revision': 2,
            'seatBindings': [],
            'groupProducts': [],
            'areaBindings': []
          };
        })));
    addTearDown(controller.dispose);
    final captured = controller.snapshot,
        pending = preparation.prepareSnapshot(captured.document, families, {});
    final changed = document.copyWith(nodes: [
      document.nodes.first.copyWith(properties: {'text': 'later text'}),
      ...document.nodes.skip(1)
    ]);
    expect(controller.layout.apply(changed), isTrue);
    wait.complete(reply(batch));
    final resources = await pending;
    expect(
        (await controller.save(
                captured: captured, preparedResources: resources))
            .accepted,
        isTrue);
    expect(sent!['layout'], captured.document.toJson());
    expect(sent!['textResourceIds'],
        collectLayoutTextResourceIds(document, resources));
    expect(controller.layout.document.nodes.first.properties['text'],
        'later text');
    expect(controller.isDirty, isTrue);
  });
  test('superseded UI preparation stops before dispatching another batch',
      () async {
    final many = VenueLayoutDocument(nodes: [
      for (var i = 0; i < 33; i++)
        LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            properties: {'text': 'Paragraph $i'},
            width: 200,
            height: 80)
    ]);
    final started = Completer<void>(), gate = Completer<void>();
    var calls = 0, current = true;
    final preparation = BlueprintTextPreparation((batch) async {
      calls++;
      if (calls == 1) {
        started.complete();
        await gate.future;
      }
      return reply(batch);
    });
    final pending =
        preparation.prepare(many, families, {}, stillCurrent: () => current);
    await started.future;
    current = false;
    gate.complete();
    expect(await pending, isA<BlueprintTextSuperseded>());
    expect(calls, 1,
        reason: 'No queued request may be dispatched for a replaced draft');
  });
  test(
      'captured save completes every batch despite UI preparation cancellation',
      () async {
    final many = VenueLayoutDocument(nodes: [
      for (var i = 0; i < 33; i++)
        LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            properties: {'text': 'Paragraph $i'},
            width: 200,
            height: 80)
    ]);
    final started = Completer<void>(), gate = Completer<void>();
    var calls = 0;
    final preparation = BlueprintTextPreparation((batch) async {
      calls++;
      if (calls == 1) {
        started.complete();
        await gate.future;
      }
      return reply(batch);
    });
    final pending = preparation.prepareSnapshot(many, families, {});
    await started.future;
    preparation.cancel();
    gate.complete();
    final resources = await pending;
    expect(calls, 2);
    expect((resources['textLayouts'] as Map).length, 33);
    expect(collectLayoutTextResourceIds(many, resources).length, 33);
  });
}

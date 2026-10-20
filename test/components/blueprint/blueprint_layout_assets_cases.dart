import '../../support/fixtures/blueprint_font_registry_fixture.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_resources.dart';
import 'package:fstapp/components/blueprint/blueprint_legacy_converter.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';

final _raster = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC');
Map<String, dynamic> _resources({int width = 2}) {
  final hash = sha256.convert(_raster).toString();
  return {
    'protocol': 2,
    'fontFamilies': <String, dynamic>{},
    'textLayouts': <String, dynamic>{},
    'assets': {
      'image:$hash': {
        'hash': hash,
        'url': 'https://images.example.test/layout.png',
        'width': width,
        'height': 2,
        'mimeType': 'image/png',
        'byteLength': _raster.length
      }
    }
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> corpusEntry() => Map<String, dynamic>.from((jsonDecode(
      File('test/fixtures/blueprint/canonical-text-sql-roundtrip.json')
          .readAsStringSync()) as Map)['admin'] as Map);

  test('late image contribution preserves current text resources and history',
      () async {
    final fixture = corpusEntry();
    final controller = VenueLayoutController(
        VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(fixture['document'] as Map)),
        resources: _resources());
    addTearDown(controller.dispose);
    final response = Completer<http.Response>();
    final resolver = BlueprintLayoutAssetResolver(
        client: MockClient((_) => response.future));
    addTearDown(resolver.dispose);
    final requested = controller.resources;
    final pending = resolver.resolve(requested);
    final prepared = Map<String, dynamic>.from(fixture['resources'] as Map);
    expect(commitBlueprintTextResources(controller, prepared), isTrue);
    response.complete(http.Response.bytes(_raster, 200));
    expect(
        commitBlueprintImages(controller,
            requestedResources: requested, resolvedResources: await pending),
        isTrue);
    expect(controller.resources['textLayouts'], prepared['textLayouts']);
    expect(controller.resources['fontFamilies'], prepared['fontFamilies']);
    expect((controller.resources['images'] as Map).length, 1);
    expect(controller.dirty, isFalse);
    expect(controller.canUndo, isFalse);
  });

  for (final removed in [false, true]) {
    test(
        'late image does not restore ${removed ? 'deleted' : 'replaced'} manifest',
        () async {
      final fixture = corpusEntry();
      final controller = VenueLayoutController(
          VenueLayoutDocument.fromJson(
              Map<String, dynamic>.from(fixture['document'] as Map)),
          resources: _resources());
      addTearDown(controller.dispose);
      final response = Completer<http.Response>();
      final resolver = BlueprintLayoutAssetResolver(
          client: MockClient((_) => response.future));
      addTearDown(resolver.dispose);
      final requested = controller.resources;
      final pending = resolver.resolve(requested);
      final ref = (requested['assets'] as Map).keys.single as String;
      final replacement = {
        ...(requested['assets'] as Map)[ref] as Map,
        'url': 'https://images.example.test/replaced.png'
      };
      expect(
          controller.setResources({
            'protocol': 2,
            'fontFamilies': <String, dynamic>{},
            'textLayouts': <String, dynamic>{},
            'assets': {if (!removed) ref: replacement}
          }),
          isTrue);
      response.complete(http.Response.bytes(_raster, 200));
      expect(
          commitBlueprintImages(controller,
              requestedResources: requested, resolvedResources: await pending),
          isTrue);
      expect(controller.resources['assets'], {if (!removed) ref: replacement});
      expect(controller.resources['images'], isEmpty);
      expect(controller.dirty, isFalse);
      expect(controller.canUndo, isFalse);
    });
  }

  test('prepared text cannot restore deleted assets or erase later images',
      () async {
    final fixture = corpusEntry();
    final resolver = BlueprintLayoutAssetResolver(
        client: MockClient((_) async => http.Response.bytes(_raster, 200)));
    addTearDown(resolver.dispose);
    final decoded = await resolver.resolve(_resources());
    final controller = VenueLayoutController(
        VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(fixture['document'] as Map)),
        resources: decoded);
    addTearDown(controller.dispose);
    final prepared = Map<String, dynamic>.from(fixture['resources'] as Map);
    final frozen = jsonEncode(prepared);
    expect(commitBlueprintTextResources(controller, prepared), isTrue);
    expect(controller.resources['assets'], decoded['assets']);
    expect(controller.resources['images'], decoded['images']);
    expect(jsonEncode(prepared), frozen);
    final stalePrepared = {...prepared, ...decoded};
    expect(
        controller.setResources(
            {...controller.resources, 'assets': {}, 'images': {}}),
        isTrue);
    expect(commitBlueprintTextResources(controller, stalePrepared), isTrue);
    expect(controller.resources['assets'], isEmpty);
    expect(controller.resources['images'], isEmpty);
    expect(controller.dirty, isFalse);
    expect(controller.canUndo, isFalse);
  });

  test('new upload contributes manifest and image without replacing live text',
      () async {
    final fixture = corpusEntry();
    final prepared = Map<String, dynamic>.from(fixture['resources'] as Map);
    final controller = VenueLayoutController(
        VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(fixture['document'] as Map)),
        resources: prepared);
    addTearDown(controller.dispose);
    final resolver = BlueprintLayoutAssetResolver(
        client: MockClient((_) async => http.Response.bytes(_raster, 200)));
    addTearDown(resolver.dispose);
    final request = _resources();
    final decoded = await resolver.resolve(request);
    expect(
        commitBlueprintImages(controller,
            requestedResources: request,
            resolvedResources: decoded,
            addAssets: true),
        isTrue);
    expect(controller.resources['assets'], request['assets']);
    expect(controller.resources['images'], decoded['images']);
    expect(controller.resources['textLayouts'], prepared['textLayouts']);
    expect(controller.dirty, isFalse);
    expect(controller.canUndo, isFalse);
    final ref = (request['assets'] as Map).keys.single as String;
    final replacement = {
      ...(request['assets'] as Map)[ref] as Map,
      'url': 'https://images.example.test/newer.png'
    };
    expect(
        controller.setResources({
          ...controller.resources,
          'assets': {ref: replacement},
          'images': {}
        }),
        isTrue);
    expect(
        commitBlueprintImages(controller,
            requestedResources: request,
            resolvedResources: decoded,
            addAssets: true),
        isFalse);
    expect((controller.resources['assets'] as Map)[ref], replacement);
    expect(controller.resources['images'], isEmpty);
  });

  test('disposed resolver rejects a pending decode', () async {
    final response = Completer<http.Response>();
    final resolver = BlueprintLayoutAssetResolver(
        client: MockClient((_) => response.future));
    final pending = resolver.resolve(_resources());
    final rejected = expectLater(pending, throwsStateError);
    resolver.dispose();
    response.complete(http.Response.bytes(_raster, 200));
    await rejected;
  });
  test(
      'canonical SQL save read copy and setup projections render prepared paths',
      () {
    final corpus = jsonDecode(
        File('test/fixtures/blueprint/canonical-text-sql-roundtrip.json')
            .readAsStringSync()) as Map;
    expect(corpus.keys, unorderedEquals(['admin', 'public', 'setup', 'copy']));
    for (final entry in corpus.entries) {
      final document = VenueLayoutDocument.fromJson(
          Map<String, dynamic>.from(entry.value['document'] as Map));
      final resources =
          Map<String, dynamic>.from(entry.value['resources'] as Map);
      expect(document.schemaVersion, 2);
      expect(validateDocument(document), isEmpty,
          reason: '${entry.key} document');
      expect(validateLayoutResources(resources), isEmpty,
          reason: '${entry.key} resources');
      final scene = compileScene(document, resources: resources);
      expect(scene['issues'], isEmpty, reason: '${entry.key} scene');
      final labels = (scene['items'] as List)
          .where((item) => item['kind'] == 'glyphs')
          .toList();
      expect(labels, isNotEmpty);
      expect(labels.every((item) => (item['path'] as List).isNotEmpty), isTrue);
      expect(labels.every((item) => !item.containsKey('fontFamily')), isTrue);
    }
  });
  test('shared registry prepares whole text in the authorized scope', () async {
    final requests = <Map<String, dynamic>>[];
    final service = TicketLayoutService(transport: (body) async {
      requests.add(body);
      return {'protocol': 2};
    });
    final provider = await BlueprintTextResources.load(42, service: service);
    expect(provider.families.length, greaterThan(1000));
    final font =
        provider.families.firstWhere((font) => font['family'] == 'Zeyada');
    expect(font['faces'], isNotEmpty);
    final batch = <String, dynamic>{'requests': [], 'numericFaces': []};
    await provider.prepareTextBatch(batch);
    final setup = await BlueprintTextResources.forSetupDraft('draft-id',
        service: service);
    await setup.prepareTextBatch(batch);
    expect(requests, [
      {
        'occasionId': 42,
        'mode': 'layout-text',
        'resourceProtocol': 2,
        'batch': batch
      },
      {
        'setupDraftId': 'draft-id',
        'mode': 'layout-text',
        'resourceProtocol': 2,
        'batch': batch
      },
    ]);
  });
  test('verified actual raster decodes once and remains transient', () async {
    var requests = 0;
    final resolver = BlueprintLayoutAssetResolver(client: MockClient((_) async {
      requests++;
      return http.Response.bytes(_raster, 200);
    }));
    addTearDown(resolver.dispose);
    final original = _resources();
    final first = await resolver.resolve(original);
    final second = await resolver.resolve(original);
    final image = (first['images'] as Map).values.single;
    expect(image.width, 2);
    expect(image.height, 2);
    expect((second['images'] as Map).values.single, same(image));
    expect(requests, 1);
    expect(original.containsKey('images'), isFalse);
  });
  test('corrupt bytes reject without poisoning retry cache', () async {
    var requests = 0;
    final resolver = BlueprintLayoutAssetResolver(client: MockClient((_) async {
      requests++;
      final data = _raster.toList();
      if (requests == 1) data[20] ^= 1;
      return http.Response.bytes(data, 200);
    }));
    addTearDown(resolver.dispose);
    await expectLater(resolver.resolve(_resources()), throwsFormatException);
    final result = await resolver.resolve(_resources());
    expect((result['images'] as Map).length, 1);
    expect(requests, 2);
  });
  test('manifest dimensions are checked against decoded bytes', () async {
    final resolver = BlueprintLayoutAssetResolver(
        client: MockClient((_) async => http.Response.bytes(_raster, 200)));
    addTearDown(resolver.dispose);
    await expectLater(
        resolver.resolve(_resources(width: 3)), throwsFormatException);
    expect((await resolver.resolve(_resources()))['images'], isNotEmpty);
  });
  test(
      'prepared label ink inside canvas is valid even when imported text box overflows',
      () {
    final fixture = jsonDecode(
        File('test/fixtures/blueprint/canonical-text-scene.json')
            .readAsStringSync()) as Map;
    final original = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(fixture['document']));
    final families =
        Map<String, dynamic>.from(fixture['resources']['fontFamilies']);
    final label = original.nodes.first.copyWith(
        x: 1000,
        y: 100,
        width: 500,
        height: 100,
        properties: {'text': 'Stůl 9'});
    final document = original.copyWith(canvas: {
      'x': 0,
      'y': 0,
      'width': 1100,
      'height': 800,
      'fill': '#FFFFFFFF',
    }, nodes: [
      label
    ]);
    final request = nodeTextRequest(document, label, families);
    Map<String, dynamic> resources(double start) => {
          'protocol': 2,
          'fontFamilies': families,
          'numberSymbols': {},
          'textLayouts': {
            request.id: {
              'id': request.id, 'descriptor': request.resourceDescriptor,
              // Deterministic prepared outline, including empty alignment space.
              'path': [
                ['M', start, -10],
                ['L', start + 50, -10],
                ['L', start + 50, 10],
                ['L', start, 10],
                ['Z']
              ],
              'clip': request.descriptor['box'],
            }
          },
        };
    final c = VenueLayoutController(document, resources: resources(-250));
    addTearDown(c.dispose);
    expect(c.showPlacementWarnings(), isEmpty);
    expect(c.document.toJson(), document.toJson());
    expect(c.setResources(resources(150)), isTrue);
    expect(c.showPlacementWarnings().single.code, 'outside_canvas');
    expect(c.setResources({}), isTrue);
    expect(c.showPlacementWarnings().single.code, 'outside_canvas');
  });

  test('reviewed native furniture preserves stable chairs and moves together',
      () {
    final source = BlueprintModel(
        id: 10,
        occasion: 20,
        groups: [BlueprintGroupModel(id: 1, title: '1')],
        objects: [
          BlueprintObjectModel(
              id: 4, type: 'spot', x: 2, y: 3, groupId: 1, title: '1A')
        ],
        backgroundSvg: '<svg width="2" height="2"></svg>');
    expect(
        () => convertLegacyBlueprint(source,
            fontFamilies: blueprintFontRegistryFixture()),
        throwsStateError);
    const digest = 'reviewed-source-test';
    final plan = <String, dynamic>{
      'sourceSha256': digest,
      'complete': true,
      'issues': [],
      'nodes': [
        {
          'id': 'table1',
          'kind': 'table',
          'transform': {'x': 100, 'y': 180, 'rotation': 90},
          'width': 120,
          'height': 40,
          'shape': 'rect'
        },
        {
          'id': 'caption1',
          'parentId': 'table1',
          'kind': 'text',
          'label': '1',
          'text': '1',
          'transform': {'x': 0, 'y': 0, 'rotation': -90},
          'width': 60,
          'height': 30,
          'size': 24,
          'role': 'decoration'
        },
        {
          'id': 'caption1-duplicate',
          'parentId': 'table1',
          'kind': 'text',
          'label': '1',
          'text': '1',
          'transform': {'x': 0, 'y': 0, 'rotation': -90},
          'width': 60,
          'height': 30,
          'size': 24,
          'role': 'decoration'
        },
        {
          'id': 'label1',
          'kind': 'text',
          'label': 'Stůl 9',
          'text': 'Stůl 9',
          'transform': {'x': 2200, 'y': 180, 'rotation': 0},
          'width': 80,
          'height': 40,
          'size': 24,
          'align': 'left'
        }
      ],
      'tableGroups': <String, dynamic>{}
    };
    final conversion = convertLegacyBlueprint(source,
        fontFamilies: blueprintFontRegistryFixture(),
        nativePlan: plan,
        reviewedSourceSha256: digest);
    final result = conversion.snapshot;
    expect(conversion.receipt['documentImport']['targetSchema'], 2);
    expect(result.document.background, isNull);
    final text = result.document.nodes.singleWhere((n) => n.kind == 'text');
    expect(text.width, 80);
    expect(text.x, 2200);
    final table = result.document.nodes.singleWhere((n) => n.kind == 'table');
    expect(table.label, '1');
    expect(result.document.nodes.where((n) => n.kind == 'text').length, 1,
        reason: 'the imported caption is replaced by the editable table name');
    final seat = result.document.nodes.singleWhere((n) => n.kind == 'seat');
    expect(seat.parentId, table.id);
    expect(result.seatBindings[seat.id]!.spotId, 4);
    expect(result.seatBindings[seat.id]!.groupNodeId, table.id);
    expect(result.document.nodes.where((n) => n.kind == 'group'), isEmpty);
    final before = worldMatrix(result.document, seat);
    expect(before[4], closeTo(120, .002));
    expect(before[5], closeTo(168, .002));
    final moved = result.document.copyWith(nodes: [
      for (final n in result.document.nodes)
        n.id == table.id ? n.copyWith(x: n.x + 48) : n
    ]);
    final after = worldMatrix(moved, seat);
    expect(after[4] - before[4], closeTo(48, .002));
    expect(after[5], closeTo(before[5], .002));
    expect(result.document.attachments.single['targetId'], table.id);
    expect(
        () => convertLegacyBlueprint(source,
            fontFamilies: blueprintFontRegistryFixture(),
            nativePlan: plan,
            reviewedSourceSha256: 'stale'),
        throwsStateError);
  });
}

import 'dart:convert';
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

final _raster = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC');
Map<String, dynamic> _resources({int width = 2}) {
  final hash = sha256.convert(_raster).toString();
  return {
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
  test('reviewed native furniture preserves stable chairs and moves together', () {
    final source = BlueprintModel(id: 10, occasion: 20,
      groups: [BlueprintGroupModel(id: 1, title: '1')],
      objects: [BlueprintObjectModel(id: 4, type: 'spot', x: 2, y: 3, groupId: 1, title: '1A')],
      backgroundSvg: '<svg width="2" height="2"></svg>');
    expect(() => convertLegacyBlueprint(source), throwsStateError);
    const digest = 'reviewed-source-test';
    final plan = <String, dynamic>{'sourceSha256': digest, 'complete': true, 'issues': [],
      'nodes': [{'id': 'table1', 'kind': 'table', 'transform': {'x': 100, 'y': 180, 'rotation': 90},
        'width': 120, 'height': 40, 'shape': 'rect'}], 'tableGroups': {'1': 'table1'}};
    final result = convertLegacyBlueprint(source, nativePlan: plan, reviewedSourceSha256: digest);
    expect(result.document.background, isNull);
    final table = result.document.nodes.singleWhere((n) => n.kind == 'table');
    final seat = result.document.nodes.singleWhere((n) => n.kind == 'seat');
    expect(seat.parentId, table.id);
    expect(result.seatBindings[seat.id]!.spotId, 4);
    expect(result.seatBindings[seat.id]!.groupNodeId, table.parentId);
    final before = worldMatrix(result.document, seat);
    expect(before[4], closeTo(120, .002)); expect(before[5], closeTo(168, .002));
    final moved = result.document.copyWith(nodes: [for (final n in result.document.nodes)
      n.id == table.id ? n.copyWith(x: n.x + 48) : n]);
    final after = worldMatrix(moved, seat);
    expect(after[4] - before[4], closeTo(48, .002));
    expect(after[5], closeTo(before[5], .002));
    expect(result.document.attachments.single['targetId'], table.id);
    expect(() => convertLegacyBlueprint(source, nativePlan: plan, reviewedSourceSha256: 'stale'), throwsStateError);
  });
}

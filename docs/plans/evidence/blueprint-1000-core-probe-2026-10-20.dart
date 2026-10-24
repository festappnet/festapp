// VM diagnostic only. This does not measure Flutter/browser frame latency.
import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, dynamic> measure(String operation, void Function() run) {
  final samples = <double>[];
  for (var i = 0; i < 10; i++) {
    final watch = Stopwatch()..start();
    run();
    if (i >= 3) samples.add(watch.elapsedMicroseconds / 1000);
  }
  samples.sort();
  return {'operation': operation, 'samples': samples.length,
    'medianMs': samples[samples.length ~/ 2], 'maxMs': samples.last};
}

void main(List<String> args) {
  final resources = Map<String, dynamic>.from(jsonDecode(File(args.single).readAsStringSync()));
  final base = rowLayout(rows: 20, seatsPerRow: 50);
  final ids = base.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet();
  require(ids.length == 1000, 'Expected 1000 actual seats');
  final original = jsonEncode(base.toJson());
  final styled = withLayoutMaterialFamily(base, 'wood');
  require(jsonEncode(base.toJson()) == original, 'Styling mutated source');
  require(styled.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet().containsAll(ids), 'Styling changed identity');
  final encoded = jsonEncode(styled.toJson());
  final restored = VenueLayoutDocument.fromJson(jsonDecode(encoded));
  require(jsonEncode(restored.toJson()) == encoded, 'Round trip lost data');
  final presentation = {ids.first: {'status': 'occupied'}};
  final scene = compileScene(restored, resources: resources, presentation: presentation);
  require((scene['issues'] as List).isEmpty, 'Scene issues: ${scene['issues']}');
  final partial = compileSceneNodes(restored, {ids.first}, resources: resources, presentation: presentation);
  final expected = (scene['items'] as List).where((i) => i['nodeId'] == ids.first || i['id'] == ids.first).toList();
  require(jsonEncode(partial['items']) == jsonEncode(expected), 'Partial and complete scene differ');
  print(jsonEncode({
    'seats': ids.length, 'nodes': restored.nodes.length,
    'documentBytes': utf8.encode(encoded).length,
    'sceneItems': (scene['items'] as List).length,
    'identityPreserved': true, 'roundTripExact': true, 'partialSceneExact': true,
    'mode': 'Dart VM JIT, warm, local fixture fonts; no browser/Flutter/network',
    'timing': [
      measure('decode_and_validate', () => VenueLayoutDocument.fromJson(jsonDecode(encoded))),
      measure('full_scene', () => compileScene(restored, resources: resources, presentation: presentation)),
      measure('one_seat_scene', () => compileSceneNodes(restored, {ids.first}, resources: resources, presentation: presentation)),
    ],
  }));
}

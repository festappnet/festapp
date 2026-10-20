import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/src/layout_editor/layout_scene_cache.dart';

// VM CPU diagnostic, not a browser frame-time claim. The controller validates
// snapshots before rendering; mirror that boundary equally for both paths.
void main() {
  for (final count in [500, 5000, 20000]) {
    final rows = rowLayout(rows: count ~/ 50, seatsPerRow: 50);
    final table = tableLayout(
      shape: 'roundedRect',
      count: count == 20000 ? 0 : 6,
    );
    final base = rows.copyWith(
      nodes: [
        for (final n in [...rows.nodes, ...table.nodes]) n.copyWith(label: ''),
      ],
    );
    final root = table.nodes.first.id;
    final cache = LayoutSceneCache();
    cache.update(base);
    final full = <int>[], partial = <int>[];
    for (var i = 0; i < 12; i++) {
      final next = base.copyWith(
        nodes: [
          for (final n in base.nodes)
            n.id == root ? n.copyWith(x: n.x + i + 1) : n,
        ],
      );
      validateDocument(next);
      worldMatrices(next);
      final timer = Stopwatch()..start();
      final patch = cache.update(next);
      final patchTime = timer.elapsedMicroseconds;
      timer.reset();
      final canonical = compileScene(next);
      if ((canonical['issues'] as List).isNotEmpty) {
        throw StateError('Invalid performance fixture: ${canonical['issues']}');
      }
      final fullTime = timer.elapsedMicroseconds;
      if (!sameLayoutValue(patch, canonical)) {
        throw StateError('Scene mismatch');
      }
      if (i >= 4) {
        partial.add(patchTime);
        full.add(fullTime);
      }
    }
    full.sort();
    partial.sort();
    stdout.writeln(
      jsonEncode({
        'staticSeats': count,
        'movingTableSeats': table.nodes.where((n) => n.kind == 'seat').length,
        'samples': full.length,
        'fullP95Ms': full[(full.length * .95).ceil() - 1] / 1000,
        'cacheP95Ms': partial[(partial.length * .95).ceil() - 1] / 1000,
        'fullMedianMs': full[full.length ~/ 2] / 1000,
        'cacheMedianMs': partial[partial.length ~/ 2] / 1000,
        'exactScenes': true,
      }),
    );
  }
}

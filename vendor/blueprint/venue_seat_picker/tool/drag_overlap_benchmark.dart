import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/src/templates/scout_hall.dart';

void main() {
  final source = scoutHall();
  final fragment = tableLayout(
    shape: 'rect',
    x: 1600,
    y: 1600,
    width: 348.75,
    height: 193.75,
    seating: const TableSeating(
      width: 77.5,
      height: 77.5,
      gap: 11.25,
      spacing: 22.5,
      edgePadding: 0,
    ),
  );
  final table = fragment.nodes.firstWhere((n) => n.kind == 'table');
  final d = source.copyWith(
    nodes: [...source.nodes, ...fragment.nodes],
    attachments: [...source.attachments, ...fragment.attachments],
  );
  final matrices = worldMatrices(d);
  final blocked = source.nodes
      .where((n) => n.kind == 'table')
      .map((n) => [matrices[n.id]![4], matrices[n.id]![5]])
      .toList();
  Map<String, Object> run(List<List<double>> points) {
    final times = <int>[];
    var rejected = 0;
    for (var i = 0; i < 90; i++) {
      final point = points[i % points.length];
      final watch = Stopwatch()..start();
      final result = moveLayoutWithinCanvas(
        d,
        {table.id},
        dx: point[0] - table.x,
        dy: point[1] - table.y,
      );
      watch.stop();
      if (i >= 30) {
        times.add(watch.elapsedMicroseconds);
        if (identical(result, d)) rejected++;
      }
    }
    times.sort();
    return {
      'medianUs': times[times.length ~/ 2],
      'p95Us': times[(times.length * .95).floor()],
      'rejected': rejected,
      'samples': times.length,
    };
  }

  stdout.writeln(
    jsonEncode({
      'blocked': run(blocked),
      'free': run([
        for (var i = 0; i < 12; i++) [1400.0 + i * 4, 1400.0 + i * 3],
      ]),
    }),
  );
}

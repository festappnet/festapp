import 'dart:convert';
import 'dart:io';

import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/src/templates/scout_hall.dart';

// VM geometry diagnostic, not a browser frame-rate claim. An optional private
// layout file reproduces a saved hall without checking organizer data into git.
void main(List<String> args) {
  final source = args.isEmpty
      ? scoutHall()
      : VenueLayoutDocument.fromJson(
          jsonDecode(File(args.first).readAsStringSync()),
        );
  final seating = documentTableSeating(source);
  for (final shape in ['rect', 'ellipse', 'bar']) {
    final fragment = shape == 'bar'
        ? barLayout(
            count: 3,
            x: 1600,
            y: 1500,
            width: 400,
            height: 140,
            seating: seating,
          )
        : tableLayout(
            shape: shape,
            x: 1600,
            y: 1500,
            width: 160 * seating.width / 40,
            height: 160 * seating.width / 40,
            seating: seating,
          );
    final table = fragment.nodes.firstWhere((node) => node.kind == 'table');
    final document = source.copyWith(
      nodes: [...source.nodes, ...fragment.nodes],
      attachments: [...source.attachments, ...fragment.attachments],
    );
    final samples = <int>[];
    var rejected = 0;
    for (var i = 0; i < 100; i++) {
      final timer = Stopwatch()..start();
      final next = translateLayoutWithinCanvas(
        document,
        {table.id},
        dx: (i % 40) * 3.0,
        dy: (i % 40) * 2.0,
      );
      timer.stop();
      if (i < 40) continue;
      samples.add(timer.elapsedMicroseconds);
      if (identical(next, document)) rejected++;
    }
    samples.sort();
    final medianMs = samples[samples.length ~/ 2] / 1000;
    stdout.writeln(
      jsonEncode({
        'shape': shape,
        'nodes': document.nodes.length,
        'samples': samples.length,
        'medianMs': medianMs,
        'p95Ms': samples[(samples.length * .95).floor()] / 1000,
        'rejected': rejected,
      }),
    );
    if (args.length > 1 && medianMs > double.parse(args[1])) {
      throw StateError('$shape table movement exceeds ${args[1]} ms median');
    }
  }
}

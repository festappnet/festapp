// Regenerate the Dart reference scenes consumed by the distributed JS parity test.
// Run from the host root with: fvm dart run automation/blueprint_export_sql_scenes.dart
import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  final corpus = jsonDecode(File(
          'test/fixtures/blueprint/canonical-text-sql-roundtrip.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final output = <String, dynamic>{};
  for (final entry in corpus.entries) {
    final raw = Map<String, dynamic>.from(entry.value['document'] as Map);
    final document = VenueLayoutDocument.fromJson(raw);
    final resources = Map<String, dynamic>.from(entry.value['resources'] as Map);
    final scene = compileScene(document, resources: resources);
    if ((scene['issues'] as List).isNotEmpty) {
      throw StateError('${entry.key}: ${scene['issues']}');
    }
    output[entry.key] = {
      'document': raw,
      'scene': scene,
      'selectionUnits': raw['selectionUnits'],
    };
  }
  File('test/fixtures/blueprint/canonical-text-sql-scenes.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(output)}\n');
  stdout.writeln('Exported ${output.length} canonical Dart reference scenes');
}

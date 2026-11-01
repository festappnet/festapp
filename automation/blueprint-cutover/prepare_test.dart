// Offline migration preparation with identity and geometry proofs. No network or DB writes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'legacy_converter.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';

void main() {
  test('prepare all legacy plans with exact physical identity and world geometry', () {
    const directory = String.fromEnvironment('BLUEPRINT_CUTOVER_DIRECTORY');
    if (directory.isEmpty)
      throw StateError('Explicit protected input directory required');
    final rows =
        jsonDecode(File('$directory/source.json').readAsStringSync()) as List;
    final catalog = jsonDecode(
      File('supabase/functions/_shared/ticket-assets/font-catalog.json')
          .readAsStringSync(),
    ) as Map;
    final families = {
      for (final f in catalog['families'] as List)
        f['id'] as String: Map<String, dynamic>.from(f),
    };
    final proposals = <Map<String, dynamic>>[];
    var seats = 0, tables = 0;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final source = Map<String, dynamic>.from(row['source'] as Map);
      final id = source['id'] as int;
      late BlueprintLayoutSnapshot snapshot;
      if (row['layout'] is Map) {
        expect((row['layout'] as Map)['schemaVersion'], 1);
        expect(source['spots'], isEmpty);
        expect(source['objects'] ?? [], isEmpty);
        final imported = importLegacyLayout(
          Map<String, dynamic>.from(row['layout']),
          fontFamilies: families,
          sourceRevision: row['layout_revision'],
        );
        expect(imported.isReady, isTrue, reason: '$id: ${imported.receipt}');
        snapshot = BlueprintLayoutSnapshot(
          blueprintId: id,
          occasionId: source['occasion'],
          title: source['title'] ?? '',
          revision: row['layout_revision'],
          document: imported.document!,
          seatBindings: const {},
        );
      } else {
        Map<String, dynamic>? native;
        if ((source['background_svg'] as String? ?? '').isNotEmpty) {
          native = jsonDecode(
            File('$directory/native$id.json').readAsStringSync(),
          ) as Map<String, dynamic>;
        }
        final converted = convertLegacyBlueprint(
          BlueprintModel.fromLegacyJson(source),
          fontFamilies: families,
          nativePlan: native,
          reviewedSourceSha256: native?['sourceSha256'] as String?,
        );
        snapshot = converted.snapshot;
      }
      final document = snapshot.document;
      expect(validateDocument(document), isEmpty, reason: 'plan $id');
      expect(document.toJson()['schemaVersion'], 2);
      final spots = {
        for (final s in source['spots'] as List)
          s['id'] as int: Map<String, dynamic>.from(s),
      };
      final objects = {
        for (final o in source['objects'] as List? ?? [])
          if (o['type'] == 'spot') o['id'] as int: Map<String, dynamic>.from(o),
      };
      expect(
        snapshot.seatBindings.length,
        spots.length,
        reason: 'every physical spot is mapped exactly once',
      );
      expect(
        snapshot.seatBindings.values.map((b) => b.spotId).toSet(),
        spots.keys.toSet(),
      );
      for (final binding in snapshot.seatBindings.values) {
        final spot = spots[binding.spotId]!, object = objects[binding.spotId]!;
        final node = document.nodes.singleWhere((n) => n.id == binding.nodeId);
        final position = worldMatrix(document, node);
        expect(position[4], closeTo((object['x'] as num) * 48 + 24, .002));
        expect(position[5], closeTo((object['y'] as num) * 48 + 24, .002));
        expect(binding.productId, spot['product']);
        expect(binding.title, spot['title'] ?? '');
        expect(binding.blocked, spot['state'] == 'black');
        final group = object['group'];
        final expectedGroup = group == null
            ? null
            : const Uuid().v5(
                Uuid.NAMESPACE_URL,
                'festapp:occasion:${source['occasion']}:blueprint:$id:group:$group',
              );
        expect(binding.groupNodeId, expectedGroup);
        if (expectedGroup != null) {
          final oldGroup = (source['groups'] as List).singleWhere(
            (g) => g['id'] == group,
          );
          expect(
            document.nodes.singleWhere((n) => n.id == expectedGroup).label,
            oldGroup['title'] ?? '',
          );
        }
      }
      final nativeFile = File('$directory/native$id.json');
      if (nativeFile.existsSync()) {
        final native = jsonDecode(nativeFile.readAsStringSync()) as Map;
        final groups = native['tableGroups'] as Map;
        expect(
          document.nodes.where((n) => n.kind == 'table').length,
          groups.length,
        );
        for (final entry in groups.entries) {
          final nodeId = const Uuid().v5(
            Uuid.NAMESPACE_URL,
            'festapp:occasion:${source['occasion']}:blueprint:$id:group:${entry.key}',
          );
          final table = document.nodes.singleWhere((n) => n.id == nodeId);
          final before = (native['nodes'] as List).singleWhere(
            (n) => n['id'] == entry.value,
          );
          final position = worldMatrix(document, table);
          expect(position[4], closeTo((before['x'] as num).toDouble(), .002));
          expect(position[5], closeTo((before['y'] as num).toDouble(), .002));
          expect(
            table.width,
            closeTo((before['width'] as num).toDouble(), .002),
          );
          expect(
            table.height,
            closeTo((before['height'] as num).toDouble(), .002),
          );
          final oldGroup = (source['groups'] as List).singleWhere(
            (g) => g['id'].toString() == entry.key,
          );
          expect(table.label, oldGroup['title']);
          expect(
            document.nodes
                .where((n) => n.kind == 'seat' && n.parentId == table.id)
                .length,
            objects.values
                .where((o) => o['group'].toString() == entry.key)
                .length,
          );
        }
      }
      final numeric = collectNumericFontFaces(
        document,
        families,
        includePresets: true,
      );
      final numericRequests = [
        for (final face in numeric)
          for (final family in families.values)
            if ((family['faces'] as Map).containsValue(face))
              {'fontFamilyId': family['id'], 'fontFaceId': face},
      ];
      final canonical = snapshot.toJson();
      proposals.add({
        'source': source,
        'beforeLayout': row['layout'],
        'beforeRevision': row['layout_revision'],
        ...canonical,
        'requests': collectTextRequests(
          document,
          families,
          includePresets: true,
        ).values.map((r) => r.descriptor).toList(),
        'numericFaces': numericRequests,
      });
      seats += spots.length;
      tables += document.nodes.where((n) => n.kind == 'table').length;
    }
    File('$directory/proposals.json').writeAsStringSync(jsonEncode(proposals));
    stdout.writeln(
      'Prepared ${proposals.length} plans, $seats exact spot bindings, $tables native tables',
    );
  });
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('export canonical template requests for bundled locales', () {
    const catalogPath = String.fromEnvironment('FONT_CATALOG');
    const outputPath = String.fromEnvironment('REQUEST_OUTPUT');
    final catalog = jsonDecode(File(catalogPath).readAsStringSync()) as Map;
    final families = {
      for (final f in catalog['families'] as List)
        f['id'] as String: Map<String, dynamic>.from(f),
    };
    final requests = <String, Map<String, dynamic>>{};
    for (final locale in ['en', 'cs']) {
      for (final template in VenueLayoutTemplates.all) {
        final d = template.create(
          localize: VenueLayoutLocalizations(Locale(locale)).text,
        );
        expect(validateDocument(d), isEmpty, reason: '${template.id}/$locale');
        for (final r in collectTextRequests(
          d,
          families,
          includePresets: true,
        ).values) {
          requests[r.id] = r.toJson();
        }
      }
    }
    final corpus = <VenueLayoutDocument>[
      busLayout(decks: 2),
      compartmentLayout(),
      VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            width: 400,
            height: 60,
            properties: {'text': 'Stage'},
            style: {
              'label': {'size': 24},
            },
          ),
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            width: 190,
            height: 110,
            label: '21',
            surface: {'type': 'rect'},
          ),
        ],
      ),
      VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            width: 700,
            height: 100,
            label: 'Stůl 16',
            surface: {'type': 'rect'},
            style: {
              'label': {'size': 60},
            },
          ),
        ],
      ),
      VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            properties: {'text': 'A'},
          ),
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            label: 'A',
            surface: {'type': 'rect'},
          ),
          LayoutNode(id: newLayoutId(), kind: 'shape', label: 'A'),
        ],
      ),
    ];
    for (final height in [100.0, 160.0]) {
      corpus.add(
        VenueLayoutDocument(
          nodes: [
            LayoutNode(
              id: newLayoutId(),
              kind: 'table',
              width: 160,
              height: height,
              label: 'Table 1',
              surface: {'type': height == 160 ? 'circle' : 'rect'},
            ),
          ],
        ),
      );
    }
    for (final d in corpus) {
      for (final request in collectTextRequests(d, families).values) {
        requests[request.id] = request.toJson();
      }
    }
    File(outputPath).writeAsStringSync(jsonEncode(requests.values.toList()));
    expect(requests, isNotEmpty);
  });
}

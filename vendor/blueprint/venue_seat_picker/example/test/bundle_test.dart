import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker_example/demo/bundle.dart';
import 'package:venue_seat_picker_example/demo/text_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent prepared text retains live images and rejects immutable collisions',
    () {
      final image = Object();
      final current = <String, dynamic>{
        'protocol': 2,
        'images': {'image:one': image},
        'textLayouts': {
          'one': {'id': 'one'},
        },
      };
      final merged = mergeDemoTextResources(current, {
        'textLayouts': {
          'two': {'id': 'two'},
        },
      });
      expect((merged['images'] as Map)['image:one'], same(image));
      expect((merged['textLayouts'] as Map).keys, containsAll(['one', 'two']));
      expect(
        mergeDemoTextResources(merged, {
          'textLayouts': {
            'two': {'id': 'two'},
          },
        }),
        same(merged),
      );
      expect(
        () => mergeDemoTextResources(merged, {
          'textLayouts': {
            'one': {'id': 'changed'},
          },
        }),
        throwsFormatException,
      );
      expect(current['textLayouts'], {
        'one': {'id': 'one'},
      });
    },
  );
  test(
    'text preparation retains current and saved requests for the same object',
    () async {
      final fixtures = await loadLayoutFixtureResources();
      final families = Map<String, dynamic>.from(
        fixtures['fontFamilies'] as Map,
      );
      final layouts = Map<String, dynamic>.from(fixtures['textLayouts'] as Map);
      final textLayouts = layouts.entries.where(
        (entry) =>
            ((entry.value as Map)['descriptor'] as Map)['request']['role'] ==
            'text',
      );
      final saved = textLayouts.first;
      final savedDescriptor =
          (saved.value as Map)['descriptor']['request'] as Map;
      final changed = textLayouts.firstWhere(
        (entry) =>
            (entry.value as Map)['descriptor']['request']['fontFaceId'] !=
            savedDescriptor['fontFaceId'],
      );
      VenueLayoutDocument document(MapEntry<String, dynamic> prepared) {
        final descriptor =
            (prepared.value as Map)['descriptor']['request'] as Map;
        final face =
            ((families[descriptor['fontFamilyId']] as Map)['faces'] as Map)
                .entries
                .firstWhere((entry) => entry.value == descriptor['fontFaceId'])
                .key
                .toString()
                .split(':');
        final box = descriptor['box'] as Map;
        final node = LayoutNode(
          id: '00000000-0000-4000-8000-000000000123',
          kind: 'text',
          x: 2000,
          y: 1500,
          width: (box['width'] as num).toDouble(),
          height: (box['height'] as num).toDouble(),
          properties: {'text': descriptor['text']},
          style: {
            'label': {
              for (final key in [
                'fontFamilyId',
                'size',
                'language',
                'direction',
                'lineHeight',
                'align',
              ])
                key: descriptor[key],
              'weight': int.parse(face[0]),
              'italic': face[1] == 'italic',
            },
          },
        );
        final empty = VenueLayoutDocument.empty();
        final result = empty.copyWith(
          canvas: {...empty.canvas, 'width': 4000, 'height': 3000},
          nodes: [node],
        );
        expect(nodeTextRequest(result, node, families).id, prepared.key);
        return result;
      }

      final baseline = document(saved), current = document(changed);
      final cached = Map<String, dynamic>.from(layouts)
        ..remove(saved.key)
        ..remove(changed.key);
      final requested = <String>{};
      final prepared = await prepareDemoText(
        current,
        {...fixtures, 'textLayouts': cached},
        baseline: baseline,
        prepareBatch: (batch) async {
          final ids = (batch['requests'] as List)
              .map(
                (request) => LayoutTextRequest(
                  Map<String, dynamic>.from(request as Map),
                ).id,
              )
              .toSet();
          requested.addAll(ids);
          // Real canonical resources replace the browser shaper at the transport seam.
          return {
            'protocol': 2,
            'fontFamilies': families,
            'textLayouts': {for (final id in ids) id: layouts[id]},
            'numberSymbols': {},
          };
        },
      );
      expect(requested, {saved.key, changed.key});
      final portable = DemoBundle(current, prepared, {
        'savedBaseline': baseline.toJson(),
      }).encode();
      expect(
        DemoBundle.decode(
          Uint8List.fromList(utf8.encode(portable)),
        ).document.toJson(),
        current.toJson(),
      );
    },
  );

  test(
    'portable metadata retains supported templates outside the current gallery',
    () async {
      final resources = await loadLayoutFixtureResources();
      for (final id in ['lounge', 'ball-classic']) {
        expect(VenueLayoutTemplates.all.any((t) => t.id == id), isFalse);
        final document = VenueLayoutTemplates.create(id);
        final encoded = DemoBundle(document, resources, {
          'template': id,
        }).encode();
        expect(
          DemoBundle.decode(
            Uint8List.fromList(utf8.encode(encoded)),
          ).host['template'],
          id,
        );
        expect(
          () => DemoBundle(document, resources, {
            'template': 'unknown-template',
          }).encode(),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'portable bundle validates version and hashes before returning a draft',
    () async {
      final doc = VenueLayoutTemplates.create('lounge');
      final resources = await loadLayoutFixtureResources();
      final bundle = DemoBundle(doc, resources, {
        'prices': {doc.nodes.firstWhere((n) => n.kind == 'seat').id: 250},
      });
      final encoded = bundle.encode();
      final decoded = DemoBundle.decode(
        Uint8List.fromList(utf8.encode(encoded)),
      );
      expect(decoded.document.toJson(), bundle.document.toJson());
      expect(decoded.host, bundle.host);
      final corrupt = jsonDecode(encoded) as Map<String, dynamic>;
      (corrupt['resources'] as List).first['sha256'] = 'bad';
      expect(
        () => DemoBundle.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(corrupt))),
        ),
        throwsFormatException,
      );
      (corrupt['resources'] as List).first['path'] = '../escape.json';
      expect(
        () => DemoBundle.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(corrupt))),
        ),
        throwsFormatException,
      );
      corrupt['version'] = 99;
      expect(
        () => DemoBundle.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(corrupt))),
        ),
        throwsFormatException,
      );
    },
  );
  test('portable envelope preserves verified embedded raster bytes', () async {
    final doc = VenueLayoutTemplates.create('blank');
    final resources = await loadLayoutFixtureResources();
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC',
    );
    final hash = sha256.convert(bytes).toString();
    resources['assets'] = {
      'image:$hash': {
        'url': 'data:image/png;base64,${base64Encode(bytes)}',
        'byteLength': bytes.length,
        'hash': hash,
        'mimeType': 'image/png',
        'width': 2,
        'height': 2,
      },
    };
    // Bundle validation covers byte transport. Native image decoding remains a
    // separate transactional host gate; this fixture does not impersonate it.
    final encoded = DemoBundle(doc, resources, {'prices': {}}).encode();
    final loaded = DemoBundle.decode(Uint8List.fromList(utf8.encode(encoded)));
    expect(
      loaded.resources['assets']['image:$hash']['byteLength'],
      bytes.length,
    );
  });
  test(
    'valid checksum cannot hide a corrupt text path or orphan host binding',
    () async {
      final doc = VenueLayoutTemplates.create('ball-classic');
      final resources = await loadLayoutFixtureResources();
      final original = DemoBundle(doc, resources, {'prices': {}}).encode();
      final corrupted = jsonDecode(original) as Map<String, dynamic>;
      final entry = (corrupted['resources'] as List).first as Map;
      final resource =
          jsonDecode(utf8.decode(base64Decode(entry['data'] as String))) as Map;
      (resource['textLayouts'] as Map).values.first['path'] = [
        ['M', 1],
      ];
      final bytes = utf8.encode(jsonEncode(resource));
      entry['data'] = base64Encode(bytes);
      entry['size'] = bytes.length;
      entry['sha256'] = sha256.convert(bytes).toString();
      expect(
        () => DemoBundle.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(corrupted))),
        ),
        throwsFormatException,
      );
      for (final invalid in [
        <dynamic>[],
        {
          'image:x': {'data': '', 'url': 'https://example.com/image.png'},
        },
      ]) {
        final malformed = jsonDecode(original) as Map<String, dynamic>;
        final item = (malformed['resources'] as List).first as Map;
        final payload =
            jsonDecode(utf8.decode(base64Decode(item['data'] as String)))
                as Map;
        payload['assets'] = invalid;
        final bytes = utf8.encode(jsonEncode(payload));
        item['data'] = base64Encode(bytes);
        item['size'] = bytes.length;
        item['sha256'] = sha256.convert(bytes).toString();
        expect(
          () => DemoBundle.decode(
            Uint8List.fromList(utf8.encode(jsonEncode(malformed))),
          ),
          throwsFormatException,
        );
      }
      final orphan = jsonDecode(original) as Map<String, dynamic>;
      orphan['host']['prices'] = {newLayoutId(): 250};
      expect(
        () => DemoBundle.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(orphan))),
        ),
        throwsFormatException,
      );
      final private = jsonDecode(original) as Map<String, dynamic>;
      private['host']['secret'] = 'must-not-enter-demo-contract';
      expect(
        () => DemoBundle.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(private))),
        ),
        throwsFormatException,
      );
      expect(
        DemoBundle.decode(
          Uint8List.fromList(utf8.encode(original)),
        ).document.toJson(),
        doc.toJson(),
      );
    },
  );
}

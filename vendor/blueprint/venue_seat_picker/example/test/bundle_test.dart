import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker_example/demo/bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

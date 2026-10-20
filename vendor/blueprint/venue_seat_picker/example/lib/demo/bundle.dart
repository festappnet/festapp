import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Versioned local file. Host metadata never enters the geometric document.
class DemoBundle {
  DemoBundle(this.document, this.resources, this.host);
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources, host;
  static const maxBytes = 16 * 1024 * 1024;
  static const maxAssetBytes = 800 * 1024;
  String encode() {
    final portable = Map<String, dynamic>.from(resources)..remove('images');
    _validateResources(portable);
    final baseline = _validateHost(host, document);
    _validateReferences(document, portable);
    if (baseline != null) {
      _validateReferences(baseline, portable);
    }
    final resourceBytes = utf8.encode(jsonEncode(portable));
    final payload = jsonEncode({
      'format': 'venue-layout-demo',
      'version': 2,
      'protocol': 1,
      'layout': document.toJson(),
      'host': host,
      'resources': [
        {
          'path': 'resources/fixtures.json',
          'size': resourceBytes.length,
          'sha256': sha256.convert(resourceBytes).toString(),
          'data': base64Encode(resourceBytes),
        },
      ],
    });
    if (utf8.encode(payload).length > maxBytes) {
      throw const FormatException('Export exceeds 16 MiB');
    }
    return payload;
  }

  static DemoBundle decode(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Import exceeds 16 MiB');
    }
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (value.keys.any(
      (k) => !const {
        'format',
        'version',
        'protocol',
        'layout',
        'host',
        'resources',
      }.contains(k),
    )) {
      throw const FormatException('Unknown portable bundle field');
    }
    if (value['format'] != 'venue-layout-demo' ||
        value['version'] != 2 ||
        value['protocol'] != 1) {
      throw const FormatException('Unsupported demo file version');
    }
    final loaded = <String, Uint8List>{};
    for (final item in value['resources'] as List) {
      final resource = item as Map<String, dynamic>;
      if (resource.keys.any(
        (k) => !const {'path', 'size', 'sha256', 'data'}.contains(k),
      )) {
        throw const FormatException('Unknown portable resource field');
      }
      final path = resource['path'] as String;
      if (!RegExp(r'^resources/[a-zA-Z0-9_-]+\.json$').hasMatch(path) ||
          loaded.containsKey(path) ||
          path != 'resources/fixtures.json') {
        throw const FormatException('Invalid or duplicate resource path');
      }
      final data = base64Decode(resource['data'] as String);
      if (data.length > maxBytes ||
          data.length != resource['size'] ||
          sha256.convert(data).toString() != resource['sha256']) {
        throw const FormatException('Resource size or SHA256 does not match');
      }
      loaded[path] = data;
    }
    final resources =
        jsonDecode(
              utf8.decode(
                loaded['resources/fixtures.json'] ??
                    (throw const FormatException('Missing local resources')),
              ),
            )
            as Map<String, dynamic>;
    _validateResources(resources);
    final document = VenueLayoutDocument.fromJson(
      value['layout'] as Map<String, dynamic>,
    );
    final issues = validateDocument(document);
    if (issues.isNotEmpty) throw FormatException(issues.first.reason);
    final host = Map<String, dynamic>.from(value['host'] as Map);
    final baseline = _validateHost(host, document);
    _validateReferences(document, resources);
    if (baseline != null) {
      _validateReferences(baseline, resources);
    }
    return DemoBundle(document, resources, host);
  }

  static void _validateResources(Map<String, dynamic> resources) {
    // Resources are self-contained; external paths and executable SVG/HTML are rejected.
    final fontIssues = validateLayoutResources(resources);
    if (fontIssues.isNotEmpty) {
      throw FormatException('Invalid font resource: ${fontIssues.first.path}');
    }
    if (resources.keys.any(
      (k) => !const {
        'protocol',
        'fontFamilies',
        'textLayouts',
        'numberSymbols',
        'assets',
      }.contains(k),
    )) {
      throw const FormatException('Unknown portable resource field');
    }
    final assets = resources['assets'];
    if (resources.containsKey('assets') && assets is! Map) {
      throw const FormatException('Embedded assets must be a map');
    }
    if (assets is Map) {
      for (final entry in assets.entries) {
        final asset = entry.value;
        if (entry.key is! String || asset is! Map || asset['url'] is! String)
          throw const FormatException('Asset must contain embedded bytes');
        final uri = Uri.tryParse(asset['url'] as String), data = uri?.data;
        if (uri?.scheme != 'data' ||
            data == null ||
            !data.isBase64 ||
            data.mimeType != asset['mimeType'])
          throw const FormatException('Asset must contain embedded bytes');
        final bytes = data.contentAsBytes();
        if (bytes.length > maxAssetBytes ||
            bytes.length != asset['byteLength'] ||
            sha256.convert(bytes).toString() != asset['hash'])
          throw const FormatException('Invalid embedded asset');
      }
    }
  }

  static void _validateReferences(
    VenueLayoutDocument doc,
    Map<String, dynamic> resources,
  ) {
    final ref = doc.background?['assetRef'];
    if (ref != null &&
        (resources['assets'] is! Map ||
            !(resources['assets'] as Map).containsKey(ref))) {
      throw const FormatException('Missing embedded background resource');
    }
    final issues = compileScene(doc, resources: resources)['issues'] as List;
    if (issues.isNotEmpty)
      throw FormatException(
        'Missing or invalid prepared resource: ${issues.first}',
      );
  }

  static VenueLayoutDocument? _validateHost(
    Map<String, dynamic> host,
    VenueLayoutDocument doc,
  ) {
    const fields = {
      'prices',
      'template',
      'revision',
      'label',
      'savedBaseline',
      'savedPrices',
    };
    if (host.keys.any((k) => !fields.contains(k))) {
      throw const FormatException('Unknown demo metadata field');
    }
    if (host['label'] != null &&
        (host['label'] is! String || (host['label'] as String).length > 512)) {
      throw const FormatException('Invalid demo label');
    }
    if (host['savedPrices'] != null && host['savedPrices'] is! Map) {
      throw const FormatException('Invalid saved prices');
    }
    final revision = host['revision'];
    if (revision != null && (revision is! int || revision < 0)) {
      throw const FormatException('Invalid demo revision');
    }
    if (host['template'] != null &&
        !VenueLayoutTemplates.all.any((t) => t.id == host['template'])) {
      throw const FormatException('Unknown demo template');
    }
    void prices(Object? value, VenueLayoutDocument layout) {
      if (value == null) return;
      if (value is! Map) throw const FormatException('Invalid demo prices');
      final ids = layout.nodes
          .where(
            (n) => const {
              'seat',
              'table',
              'group',
              'furniture',
              'capacityArea',
            }.contains(n.kind),
          )
          .map((n) => n.id)
          .toSet();
      for (final entry in value.entries) {
        if (!ids.contains(entry.key) ||
            entry.value is! int ||
            (entry.value as int) < 0 ||
            (entry.value as int) > 100000000) {
          throw const FormatException(
            'Invalid or orphaned sample price binding',
          );
        }
      }
    }

    prices(host['prices'], doc);
    if (host['savedBaseline'] != null) {
      if (host['savedBaseline'] is! Map) {
        throw const FormatException('Invalid saved baseline');
      }
      final baseline = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(host['savedBaseline'] as Map),
      );
      if (validateDocument(baseline).isNotEmpty) {
        throw const FormatException('Invalid saved baseline');
      }
      prices(host['savedPrices'], baseline);
      return baseline;
    } else if (host['savedPrices'] is Map &&
        (host['savedPrices'] as Map).isNotEmpty) {
      throw const FormatException('Saved prices have no baseline');
    }
    return null;
  }
}

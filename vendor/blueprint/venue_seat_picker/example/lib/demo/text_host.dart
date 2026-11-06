import 'package:venue_seat_picker/venue_seat_picker.dart';

import 'text_host_stub.dart' if (dart.library.js_interop) 'text_host_web.dart';

/// The demo adapts its bundled canonical engine; the library still accepts
/// prepared resources from its host and owns no alternate shaping algorithm.
Future<Map<String, dynamic>> prepareDemoText(
  VenueLayoutDocument document,
  Map<String, dynamic> resources, {
  VenueLayoutDocument? baseline,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) prepareBatch =
      prepareTextBatch,
}) async {
  final families = Map<String, dynamic>.from(
    resources['fontFamilies'] as Map? ?? {},
  );
  // Object IDs persist across edits; each snapshot can need a different
  // immutable text resource for that same object.
  final requests = <String, LayoutTextRequest>{
    for (final snapshot in [document, ?baseline])
      for (final request in collectTextRequests(
        snapshot,
        families,
        includePresets: true,
      ).values)
        request.id: request,
  };
  final missing = requests.values
      .where((r) => !(resources['textLayouts'] as Map? ?? {}).containsKey(r.id))
      .toList();
  if (missing.isEmpty) return resources;
  var next = resources;
  Future<void> prepare(List<LayoutTextRequest> batch) async {
    if (batch.isEmpty) return;
    final result = await prepareBatch({
      'requests': batch.map((r) => r.toJson()).toList(),
      'numericFaces': [],
    });
    if (result['protocol'] != 2) {
      throw const FormatException('Invalid prepared text protocol');
    }
    final merged = mergeDemoTextResources(next, result);
    next = merged;
  }

  var batch = <LayoutTextRequest>[], characters = 0;
  for (final request in missing) {
    final length = (request.descriptor['text'] as String).runes.length;
    if (batch.length == 32 || characters + length > 8192) {
      await prepare(batch);
      batch = [];
      characters = 0;
    }
    batch.add(request);
    characters += length;
  }
  await prepare(batch);
  final issues = compileScene(document, resources: next)['issues'] as List;
  if (issues.isNotEmpty) {
    throw FormatException('Prepared text unavailable: ${issues.first}');
  }
  return next;
}

/// Merge only immutable text resources, preserving images loaded concurrently.
Map<String, dynamic> mergeDemoTextResources(
  Map<String, dynamic> current,
  Map<String, dynamic> prepared,
) {
  final next = Map<String, dynamic>.from(current);
  var changed = false;
  for (final key in ['fontFamilies', 'textLayouts', 'numberSymbols']) {
    final existing = Map<String, dynamic>.from(current[key] as Map? ?? {});
    final incoming = prepared[key] as Map? ?? {};
    for (final entry in incoming.entries) {
      if (existing.containsKey(entry.key)) {
        if (canonicalContractJson(existing[entry.key]) !=
            canonicalContractJson(entry.value)) {
          throw FormatException(
            'Immutable text resource collision: ${entry.key}',
          );
        }
      } else {
        existing[entry.key as String] = entry.value;
        changed = true;
      }
    }
    next[key] = existing;
  }
  return changed ? next : current;
}

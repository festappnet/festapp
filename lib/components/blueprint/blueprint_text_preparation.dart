import 'dart:convert';
import 'package:venue_seat_picker/venue_seat_picker.dart';

sealed class BlueprintTextPreparationResult {
  const BlueprintTextPreparationResult();
}

class BlueprintTextReady extends BlueprintTextPreparationResult {
  const BlueprintTextReady(this.document, this.resources);
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources;
}

class BlueprintTextSuperseded extends BlueprintTextPreparationResult {
  const BlueprintTextSuperseded();
}

class BlueprintTextFailed extends BlueprintTextPreparationResult {
  const BlueprintTextFailed(this.error);
  final Object error;
}

class _PreparationSuperseded implements Exception {
  const _PreparationSuperseded();
}

/// The transport admits and persists each bounded batch in its authorized scope.
/// No mutable character accumulator, client shaping or native font fallback.
class BlueprintTextPreparation {
  BlueprintTextPreparation(this.prepareBatch);
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      prepareBatch;
  int _generation = 0;
  void cancel() => _generation++;
  Future<BlueprintTextPreparationResult> prepare(VenueLayoutDocument document,
      Map<String, dynamic> families, Map<String, dynamic> currentResources,
      {bool Function()? stillCurrent}) async {
    final generation = ++_generation;
    try {
      final resources = await _prepareSnapshot(
          document, families, currentResources,
          stillCurrent: () =>
              generation == _generation && stillCurrent?.call() != false);
      if (generation != _generation || stillCurrent?.call() == false)
        return const BlueprintTextSuperseded();
      return BlueprintTextReady(document, resources);
    } on _PreparationSuperseded {
      return const BlueprintTextSuperseded();
    } catch (error) {
      if (generation != _generation || stillCurrent?.call() == false)
        return const BlueprintTextSuperseded();
      return BlueprintTextFailed(error);
    }
  }

  /// Save owns its captured snapshot even if the visible draft changes while
  /// awaiting a font. The returned document is exactly the submitted one.
  Future<Map<String, dynamic>> prepareSnapshot(
          VenueLayoutDocument document,
          Map<String, dynamic> families,
          Map<String, dynamic> currentResources) =>
      _prepareSnapshot(document, families, currentResources);

  Future<Map<String, dynamic>> _prepareSnapshot(VenueLayoutDocument document,
      Map<String, dynamic> families, Map<String, dynamic> currentResources,
      {bool Function()? stillCurrent}) async {
    void checkCurrent() {
      if (stillCurrent?.call() == false) throw const _PreparationSuperseded();
    }

    checkCurrent();
    // Scoped reads retain immutable historical manifests even after catalog
    // discovery starts offering a newer family version.
    final retained = Map<String, dynamic>.from(
        currentResources['fontFamilies'] as Map? ?? {});
    for (final entry in retained.entries) {
      if (families.containsKey(entry.key) &&
          canonicalContractJson(entry.value) !=
              canonicalContractJson(families[entry.key]))
        throw LayoutTextDependencyFailure('font_family_manifest_conflict',
            fontFamilyId: entry.key);
    }
    families = {...retained, ...families};
    final requests =
        collectTextRequests(document, families, includePresets: true);
    final unique = {for (final request in requests.values) request.id: request};
    final textLayouts = <String, dynamic>{
      ...currentResources['textLayouts'] as Map? ?? {}
    };
    final numberSymbols = <String, dynamic>{
      ...currentResources['numberSymbols'] as Map? ?? {}
    };
    final usedFamilies = <String, dynamic>{};
    for (final id
        in collectDeclaredLayoutFontFamilies(document, includePresets: true)) {
      if (families[id] is! Map)
        throw LayoutTextDependencyFailure('font_family_unavailable',
            fontFamilyId: id);
      usedFamilies[id] = families[id];
    }
    for (final request in requests.values) {
      final id = request.descriptor['fontFamilyId'] as String;
      usedFamilies[id] = families[id];
    }
    final numericFaces =
        collectNumericFontFaces(document, families, includePresets: true);
    for (final id in numericFaces) {
      final family = families.entries
          .firstWhere((f) => (f.value['faces'] as Map).containsValue(id));
      usedFamilies[family.key] = family.value;
    }
    final batches = <Map<String, dynamic>>[];
    Map<String, dynamic> empty() => {
          'requests': <Map<String, dynamic>>[],
          'numericFaces': <Map<String, dynamic>>[]
        };
    var batch = empty(), characters = 0;
    final faces = <String>{};
    for (final entry in unique.entries) {
      if (textLayouts.containsKey(entry.key)) continue;
      final request = entry.value.descriptor;
      final chars = (request['text'] as String).runes.length;
      final list = batch['requests'] as List;
      if (list.isNotEmpty &&
          (list.length == 32 ||
              characters + chars > 8192 ||
              (!faces.contains(request['fontFaceId']) && faces.length == 8) ||
              utf8
                      .encode(jsonEncode({
                        ...batch,
                        'requests': [...list, request]
                      }))
                      .length >
                  38000)) {
        batches.add(batch);
        batch = empty();
        characters = 0;
        faces.clear();
      }
      (batch['requests'] as List).add(request);
      characters += chars;
      faces.add(request['fontFaceId'] as String);
    }
    if ((batch['requests'] as List).isNotEmpty) batches.add(batch);
    final missing =
        numericFaces.where((id) => !numberSymbols.containsKey(id)).toList();
    for (var i = 0; i < missing.length; i += 8) {
      final subset = missing.skip(i).take(8);
      batches.add({
        'requests': [],
        'numericFaces': [
          for (final id in subset)
            {
              'fontFaceId': id,
              'fontFamilyId': families.entries
                  .firstWhere(
                      (f) => (f.value['faces'] as Map).containsValue(id))
                  .key
            }
        ]
      });
    }
    for (final batch in batches) {
      checkCurrent();
      final result = await prepareBatch(batch);
      checkCurrent();
      final issues = validateLayoutResources(result);
      if (issues.isNotEmpty) throw StateError(issues.first.reason);
      textLayouts
          .addAll(Map<String, dynamic>.from(result['textLayouts'] as Map));
      numberSymbols.addAll(
          Map<String, dynamic>.from(result['numberSymbols'] as Map? ?? {}));
    }
    final result = <String, dynamic>{
      'protocol': 2,
      'fontFamilies': usedFamilies,
      'textLayouts': {for (final id in unique.keys) id: textLayouts[id]},
      'numberSymbols': {for (final id in numericFaces) id: numberSymbols[id]},
      if (currentResources['assets'] != null)
        'assets': currentResources['assets'],
      if (currentResources['images'] != null)
        'images': currentResources['images']
    };
    final issues = validateLayoutResources(result);
    if (issues.isNotEmpty) throw StateError(issues.first.reason);
    for (final request in unique.values)
      if (result['textLayouts'][request.id] == null)
        throw StateError('text_layout_unavailable');
    final images = result.remove('images');
    return Map.unmodifiable(
        {...frozenMap(result), if (images != null) 'images': images});
  }
}

/// SVG keeps one complete paragraph per authored <text> element. Missing faces
/// resolve deterministically to an actual registered face and enter its receipt.
class BlueprintSvgTextPreparation {
  BlueprintSvgTextPreparation(this.families, this.prepareBatch);
  final Map<String, dynamic> families;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)
      prepareBatch;
  Future<SvgTextOutline> call(SvgTextRequest text) async {
    final names = text.family
        .split(',')
        .map((v) => v.trim().replaceAll('"', '').replaceAll("'", ''))
        .toList();
    final all = families.values.cast<Map>().toList()
      ..sort((a, b) =>
          '${a['family']}:${a['id']}'.compareTo('${b['family']}:${b['id']}'));
    Map? family;
    for (final name in names) {
      final match = all
          .where((f) => '${f['family']}'.toLowerCase() == name.toLowerCase());
      if (match.isNotEmpty) {
        family = match.first;
        break;
      }
    }
    family ??= all.where((f) => f['family'] == 'Roboto').firstOrNull ??
        all.firstOrNull;
    if (family == null) throw const GraphicImportFailure('font_registry_empty');
    final faces = Map<String, dynamic>.from(family['faces'] as Map),
        desired = '${text.weight}:${text.italic ? 'italic' : 'normal'}';
    final variants = faces.keys.toList()
      ..sort((a, b) {
        int cost(String v) {
          final p = v.split(':');
          return (p[1] == (text.italic ? 'italic' : 'normal') ? 0 : 2) +
              (p[0] == '${text.weight}' ? 0 : 1);
        }

        final c = cost(a).compareTo(cost(b));
        return c == 0 ? a.compareTo(b) : c;
      });
    if (variants.isEmpty)
      throw const GraphicImportFailure('font_face_unavailable');
    final variant = faces.containsKey(desired) ? desired : variants.first,
        face = faces[variant];
    final request = LayoutTextRequest({
      'text': text.text,
      'role': 'text',
      'fontFamilyId': family['id'],
      'fontFaceId': face,
      'size': text.size,
      'language': text.language,
      'direction': text.direction,
      'lineHeight': 1.2,
      'align': 'left',
      'fit': 'wrap',
      'box': {'x': 0, 'y': 0, 'width': 1000000000, 'height': 1000000000}
    });
    final resources = await prepareBatch({
      'requests': [request.toJson()],
      'numericFaces': []
    });
    final issues = validateLayoutResources(resources);
    if (issues.isNotEmpty) throw StateError(issues.first.reason);
    final prepared = (resources['textLayouts'] as Map)[request.id];
    if (prepared is! Map ||
        canonicalContractJson(prepared['descriptor']) !=
            canonicalContractJson(request.resourceDescriptor) ||
        prepared['lines'] is! List ||
        (prepared['lines'] as List).length != 1)
      throw const GraphicImportFailure('svg_text_preparation_invalid');
    final line = (prepared['lines'] as List).single as Map,
        x = line['x'] as num,
        y = line['baseline'] as num;
    return SvgTextOutline(
        path: [
          for (final c in prepared['path'] as List)
            [
              c[0],
              for (var i = 1; i < c.length; i += 2) ...[
                (c[i] as num) - x,
                (c[i + 1] as num) - y
              ]
            ]
        ],
        advance: (line['advance'] as num).toDouble(),
        dependency: {
          'textResourceId': request.id,
          'fontFamilyId': family['id'],
          'fontFaceId': face,
          'requestedFamily': text.family,
          'requestedWeight': text.weight,
          'requestedItalic': text.italic,
          'actualVariant': variant,
          'resolution': names.contains(family['family']) && variant == desired
              ? 'exact'
              : 'closest-actual-face',
        });
  }
}

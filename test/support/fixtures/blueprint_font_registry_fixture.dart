import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'dart:convert';
import 'dart:io';

/// Reads the same immutable catalog bundled by the application.
Map<String, Map<String, dynamic>> blueprintFontRegistryFixture() {
  final catalog = jsonDecode(
      File('supabase/functions/_shared/ticket-assets/font-catalog.json')
          .readAsStringSync()) as Map;
  return {
    for (final family in catalog['families'] as List)
      family['id'] as String: Map<String, dynamic>.from(family as Map)
  };
}

/// Descriptor-correct transport stub for business/UI tests, not shaping evidence.
/// Actual font quality is verified separately by the native/browser raster corpus.
Map<String, dynamic> blueprintPreparedResourcesFixture(
    VenueLayoutDocument document) {
  final resources = jsonDecode(File(
          'vendor/blueprint/venue_seat_picker/assets/layout_fonts/fixtures.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final families = blueprintFontRegistryFixture();
  final requests =
      collectTextRequests(document, families, includePresets: true);
  return {
    ...resources,
    'fontFamilies': {
      ...resources['fontFamilies'] as Map,
      for (final request in requests.values)
        request.descriptor['fontFamilyId']:
            families[request.descriptor['fontFamilyId']]
    },
    'textLayouts': {
      for (final request in requests.values)
        request.id: {
          'id': request.id,
          'descriptor': request.resourceDescriptor,
          'path': [
            ['M', 0, 0],
            ['L', 1, 1]
          ],
          'clip': request.descriptor['box'],
        },
    }
  };
}

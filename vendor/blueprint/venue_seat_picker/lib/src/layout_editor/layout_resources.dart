import 'dart:convert';
import 'package:flutter/services.dart';

/// Optional licensed local fixtures for examples and standalone consumers.
/// Production hosts supply their own catalog/resources through the same seam.
Future<Map<String, dynamic>> loadLayoutFixtureResources() async =>
    jsonDecode(
          await rootBundle.loadString(
            'packages/venue_seat_picker/assets/layout_fonts/fixtures.json',
          ),
        )
        as Map<String, dynamic>;

abstract class LayoutAssetProvider {
  Future<Map<String, dynamic>> resolve(String assetRef);
}

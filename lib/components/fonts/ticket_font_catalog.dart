import 'dart:convert';

import 'package:flutter/services.dart';

class TicketFontCatalog {
  static const defaultLayoutFontId =
      'builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44';
  static const _path =
      'supabase/functions/_shared/ticket-assets/font-catalog.json';
  static Future<Map<String, dynamic>>? _dataFuture;
  static Future<Map<String, dynamic>> _data() => _dataFuture ??= _read();

  static Future<Map<String, dynamic>> _read() async {
    try {
      final value = jsonDecode(
        await rootBundle.loadString(_path),
      ) as Map<String, dynamic>;
      if (value['version'] != 2)
        throw const FormatException('font_catalog_version');
      return value;
    } catch (_) {
      _dataFuture = null;
      // CachingAssetBundle also retains failed loadString futures.
      rootBundle.evict(_path);
      rethrow;
    }
  }

  static const _selectionPath =
      'automation/tickets/setup-appearance-fonts.json';
  static Future<Map<String, String>>? _setupFuture;

  /// Policy first, then immutable Google default faces in catalog order.
  static Future<Map<String, String>> loadSetupFonts() =>
      _setupFuture ??= _readSetupFonts();

  static Future<Map<String, String>> _readSetupFonts() async {
    try {
      final selection = Map<String, String>.from(
        jsonDecode(await rootBundle.loadString(_selectionPath)) as Map,
      );
      final catalog = await _data();
      final faces = (catalog['fonts'] as List).cast<Map>();
      final defaults = (catalog['defaultFaceIds'] as List).toSet();
      for (final face in faces) {
        if (face['source'] == 'google' && defaults.contains(face['id'])) {
          selection.putIfAbsent(
            face['family'] as String,
            () => face['id'] as String,
          );
        }
      }
      final byId = {for (final face in faces) face['id']: face};
      for (final entry in selection.entries) {
        final family = byId[entry.value]?['family'];
        if (family != entry.key && family != '${entry.key} (legacy)') {
          throw FormatException('Unknown immutable face for ${entry.key}');
        }
      }
      return Map.unmodifiable(selection);
    } catch (_) {
      _setupFuture = null;
      rootBundle.evict(_selectionPath);
      rethrow;
    }
  }

  /// Ticket Editor keeps its historical default face choices. Additional real
  /// faces belong to the same catalog and are selected through family manifests.
  static Future<List<Map<String, dynamic>>> load() async {
    final value = await _data();
    final defaults = (value['defaultFaceIds'] as List).toSet();
    return (value['fonts'] as List)
        .cast<Map>()
        .where((f) => defaults.contains(f['id']))
        .map((f) => f.cast<String, dynamic>())
        .toList();
  }

  static Future<List<Map<String, dynamic>>> loadFamilies() async =>
      ((await _data())['families'] as List)
          .cast<Map>()
          .map((f) => f.cast<String, dynamic>())
          .toList();
}

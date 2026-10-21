import 'dart:convert';
import 'package:flutter/services.dart';

class TicketFontCatalog {
  static const defaultLayoutFontId = 'builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44';
  static Future<Map<String, dynamic>>? _dataFuture;
  static Future<Map<String, dynamic>> _data() => _dataFuture ??= () async {
    final value = jsonDecode(await rootBundle.loadString(
        'supabase/functions/_shared/ticket-assets/font-catalog.json')) as Map<String, dynamic>;
    if (value['version'] != 2) throw const FormatException('font_catalog_version');
    return value;
  }();

  /// Ticket Editor keeps its historical default face choices. Additional real
  /// faces belong to the same catalog and are selected through family manifests.
  static Future<List<Map<String, dynamic>>> load() async {
    final value = await _data();
    final defaults = (value['defaultFaceIds'] as List).toSet();
    return (value['fonts'] as List).cast<Map>().where((f) => defaults.contains(f['id']))
        .map((f) => f.cast<String, dynamic>()).toList();
  }

  static Future<List<Map<String, dynamic>>> loadFamilies() async =>
      ((await _data())['families'] as List).cast<Map>()
          .map((f) => f.cast<String, dynamic>()).toList();
}

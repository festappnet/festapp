import 'dart:convert';
import 'package:flutter/services.dart';

class TicketFontCatalog {
  static const defaultLayoutFontId = 'builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44';
  static Future<List<Map<String, dynamic>>>? _future;
  static Future<List<Map<String, dynamic>>> load() => _future ??= _load();
  static Future<List<Map<String, dynamic>>> _load() async {
    final value = jsonDecode(await rootBundle
        .loadString('supabase/functions/_shared/ticket-assets/font-catalog.json')) as Map;
    return (value['fonts'] as List)
        .map((f) => (f as Map).cast<String, dynamic>())
        .toList();
  }
}

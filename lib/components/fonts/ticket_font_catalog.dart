import 'dart:convert';
import 'package:flutter/services.dart';

class TicketFontCatalog {
  static Future<List<Map<String, dynamic>>>? _future;
  static Future<List<Map<String, dynamic>>> load() => _future ??= _load();
  static Future<List<Map<String, dynamic>>> _load() async {
    final value = jsonDecode(await rootBundle
        .loadString('assets/fonts/ticket-font-catalog.json')) as Map;
    return (value['fonts'] as List)
        .map((f) => (f as Map).cast<String, dynamic>())
        .toList();
  }
}

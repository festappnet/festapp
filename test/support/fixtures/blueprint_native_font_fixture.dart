import 'dart:convert';
import 'dart:io';

/// Real font bytes for local draft rendering. Shaping is deliberately unavailable
/// here: ordinary editing and mode changes must not request canonical vectors.
Future<Map<String, dynamic>> blueprintNativeFontReplyFixture(
    Map<String, dynamic> request) async {
  if (request['mode'] != 'font') {
    throw StateError('Canonical vectors must wait for explicit Save');
  }
  final catalog = jsonDecode(
      File('supabase/functions/_shared/ticket-assets/font-catalog.json')
          .readAsStringSync())['fonts'] as List;
  final face = catalog.firstWhere((entry) => entry['id'] == request['fontId']);
  final file = face['file'] is String
      ? 'supabase/functions/_shared/ticket-assets/${face['file']}'
      : 'test/fixtures/ticket_fonts/${face['family'].replaceAll(' ', '-')}.ttf';
  return {
    'id': face['id'],
    'family': face['family'],
    'weight': face['weight'],
    'font': base64Encode(File(file).readAsBytesSync()),
    'metrics': jsonDecode(File('test/fixtures/ticket_layout/resolve.json')
        .readAsStringSync())['metrics'],
  };
}

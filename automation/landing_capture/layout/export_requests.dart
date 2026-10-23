// Uses the same public text collector as the editor before local fixture save.
import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';
void main(List<String> args) {
  final families = jsonDecode(File(args[0]).readAsStringSync())['families'] as List;
  final catalog = {for (final family in families) family['id'] as String: Map<String, dynamic>.from(family)};
  final doc = VenueLayoutDocument.fromJson(jsonDecode(File(args[1]).readAsStringSync()));
  final requests = collectTextRequests(doc, catalog);
  File(args[2]).writeAsStringSync(jsonEncode(requests.values.map((r) => r.toJson()).toList()));
  print('Exported ${requests.length} canonical text requests');
}

import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/venue_layout_templates.dart';

void main(List<String> args) {
  final catalog = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final families = {
    for (final f in catalog['families'] as List)
      f['id'] as String: Map<String, dynamic>.from(f),
  };
  final requests = <String, Map<String, dynamic>>{};
  for (final template in VenueLayoutTemplates.all) {
    final d = template.create();
    for (final r in collectTextRequests(
      d,
      families,
      includePresets: true,
    ).values)
      requests[r.id] = r.toJson();
  }
  File(args[1]).writeAsStringSync(jsonEncode(requests.values.toList()));
  stdout.writeln('Exported ${requests.length} canonical template requests');
}

import 'dart:convert';
import 'dart:io';
import 'package:venue_seat_picker/venue_layout_templates.dart';

void main() {
  final layout = VenueLayoutTemplates.create(VenueLayoutTemplates.defaultId);
  final resources = jsonDecode(
    File('assets/layout_fonts/fixtures.json').readAsStringSync(),
  );
  File('web/demo/seed.js').writeAsStringSync(
    'globalThis.venueDemoSeed = ${jsonEncode({'layout': layout.toJson(), 'resources': resources})};\n',
  );
  stdout.writeln('JS demo seed exported from the public template API');
}

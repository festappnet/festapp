import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/venue_layout_templates.dart';

// Actual saved palette nodes normalize equal-sided ellipses to circle.
// Mirror the real editor's _rawFragment/_fragment public factory calls.
void main(List<String> args) {
  final catalog=jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final families={for(final f in catalog['families'] as List) f['id'] as String:Map<String,dynamic>.from(f)};
  final host=VenueLayoutTemplates.create('ball-mixed');
  final seating=documentSeating(host);
  final raw=tableLayout(shape:'ellipse',x:0,y:0,width:160*seating.width/40,height:160*seating.width/40,seating:seating);
  final requests=<String,dynamic>{};
  for(final name in (args.length>2 && args[2]=='en' ? ['Table 9','Table 10'] : ['Stůl 9','Stůl 10'])) {
    final doc=raw.copyWith(styles:host.styles,seatingDefaults:host.seatingDefaults,textPolicy:host.textPolicy,nodes:[for(final n in raw.nodes)n.kind=='table'?n.copyWith(label:name,surface: const {'type':'circle'}):n]);
    for(final r in collectTextRequests(doc,families,includePresets:true).values)requests[r.id]=r.toJson();
    File('${args[1]}.$name.json').writeAsStringSync(jsonEncode(doc.toJson()));
  }
  File(args[1]).writeAsStringSync(jsonEncode(requests.values.toList()));
  print('Prepared ${requests.length} genuine palette text requests');
}

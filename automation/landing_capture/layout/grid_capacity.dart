import 'dart:io';
import 'dart:convert';
import 'package:venue_layout_core/venue_layout_core.dart';
void main(List<String> args){final d=VenueLayoutDocument.fromJson(jsonDecode(File(args[0]).readAsStringSync()));print(jsonEncode({'collisionPairs':layoutCollisions(d),'tables':[for(final n in d.nodes.where((n)=>n.kind=='table')){'id':n.id,'surface':n.surface,'capacity':tableCapacity(n),'actualSeats':d.nodes.where((s)=>s.kind=='seat'&&s.parentId==n.id).length}]}));}

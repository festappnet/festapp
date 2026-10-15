from pathlib import Path
base=Path('/tmp/festapp-bundle-audit-20261015');root=base/'source/lib/components'
for target,original in [('ticket_layout/views/ticket_layout_editor.dart','ticket-editor.original.dart'),('ticket_layout/views/ticket_settings.dart','ticket-settings.original.dart')]:
 (root/target).write_text((base/original).read_text())
(root/'ticket_layout/views/ticket_layout_result.dart').unlink()
p=root/'map/map_page.dart';original=p.read_text();(base/'map-page.original.dart').write_text(original)
start=original.index('sealed class MapEditorMode');cut=original.index('class MapPage extends StatefulWidget')
header=original[:start]
runtime=header+"import 'map_page.dart' show MapPage;\n"+original[cut:]
runtime=runtime.replace('class MapPage extends StatefulWidget','class MapPageRuntime extends StatefulWidget').replace('const MapPage({','const MapPageRuntime({').replace('State<MapPage>','State<MapPageRuntime>')
(root/'map/map_page_runtime.dart').write_text(runtime)
front="""import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'map_place_model.dart';
import 'path_group_model.dart';
import 'public_map_session.dart';
import 'map_page_runtime.dart' deferred as map_runtime;
"""+original[start:cut]+"""
class MapPage extends StatefulWidget {
 static const ROUTE = 'map';
 static final ValueNotifier<bool> isEditingNotifier = ValueNotifier(false);
 final PlaceModel? place;
 final PathGroupsModel? editPathGroup;
 const MapPage({this.place,this.editPathGroup,super.key});
 @override State<MapPage> createState()=>_LazyMapState();
}
class _LazyMapState extends State<MapPage> {
 late final Future<void> _loaded=map_runtime.loadLibrary();
 @override Widget build(BuildContext context)=>FutureBuilder<void>(future:_loaded,builder:(context,state){
  if(state.hasError)return const Center(child:Text('Map module failed to load'));
  if(state.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
  return map_runtime.MapPageRuntime(place:widget.place,editPathGroup:widget.editPathGroup);
 });
}
"""
p.write_text(front)
print('Prepared isolated own-map module experiment.')

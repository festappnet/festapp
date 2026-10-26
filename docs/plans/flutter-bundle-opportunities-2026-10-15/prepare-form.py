from pathlib import Path
base=Path('/tmp/festapp-bundle-audit-20261015');root=base/'source/lib/components'
(root/'map/map_page.dart').write_text((base/'map-page.original.dart').read_text());(root/'map/map_page_runtime.dart').unlink()
p=root/'forms/views/form_editor_content.dart';s=p.read_text();(base/'form-editor.original.dart').write_text(s)
(root/'forms/views/form_editor_runtime.dart').write_text(s.replace('FormEditorContent','FormEditorRuntime'))
start=s.index('class FormEditorContent extends StatefulWidget');end=s.index('class _FormEditorContentState',start)
cls=s[start:end].replace('_FormEditorContentState createState() => _FormEditorContentState();','State<FormEditorContent> createState() => _LazyFormEditorState();')
p.write_text("""import 'package:flutter/material.dart';
import '../db_forms.dart';
import 'form_editor_runtime.dart' deferred as form_editor;
const double kHiddenOpacity=0.5;
"""+cls+"""
class _LazyFormEditorState extends State<FormEditorContent> {
 late final Future<void> _loaded=form_editor.loadLibrary();
 @override Widget build(BuildContext context)=>FutureBuilder<void>(future:_loaded,builder:(context,state){
  if(state.hasError)return const Center(child:Text('Editor module failed to load'));
  if(state.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
  if(widget.prototypeBundle!=null)return form_editor.FormEditorRuntime.prototype(bundle:widget.prototypeBundle!,onPrototypeSave:widget.onPrototypeSave,embedded:widget.embedded);
  return form_editor.FormEditorRuntime(formLink:widget.formLink,onDataUpdated:widget.onDataUpdated,loadBundle:widget.loadBundle);
 });
}
""")
print('Prepared isolated own-form editor experiment.')

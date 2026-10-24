"""Host a canonical saved document with actual Festapp font/style resources."""
import json,subprocess,argparse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('package',type=Path);p.add_argument('--transparent-canvas',action='store_true');p.add_argument('--hide-canvas-controls',action='store_true');p.add_argument('--resume-document',type=Path);p.add_argument('--clean-stage',action='store_true');p.add_argument('--locale',choices=['cs','en'],default='cs');a=p.parse_args();base=Path(__file__).resolve().parent
subprocess.run(['python3',str(base/'prepare_host.py'),str(a.package)],check=True)
from brand_style import brand
empty=json.loads((base/'fixtures/growth-empty.cs.json').read_text());empty=brand(empty)
if a.clean_stage:
 empty['canvas']['fill']='#EBF1F6FF'
 empty['nodes']=[n for n in empty['nodes'] if n['id'] in {'982abc9a-af63-4e2e-9326-a784c6c9db3a','c0ae0f5f-5e5d-4230-826a-0295dfcb9913','e3183926-6335-4349-bd4a-1943c957b2e9'}]
 for n in empty['nodes']:
  if n.get('kind')=='shape':n['style']['fill']='#80BDF2FF'
if a.transparent_canvas:empty['canvas']['fill']='#00000000'
if a.locale=='en':
 for n in empty['nodes']:
  translations={'sloup':'column','vstup':'entrance','Pódium':'Stage','Sál':'Hall'}
  n['label']=translations.get(n.get('label'),n.get('label',''))
  if 'text' in n:n['text']=translations.get(n['text'],n['text'])
(base/f'fixtures/brand-empty.{a.locale}.json').write_text(json.dumps(empty,ensure_ascii=False,indent=2))
f=a.package/'example/lib/landing_capture.dart';s=f.read_text();s="import 'package:flutter/services.dart';\n"+s
s=s.replace('final resources = await loadLayoutFixtureResources();',"final loader=FontLoader('Futura'); loader.addFont(rootBundle.load('packages/venue_seat_picker/assets/layout_fonts/Futura.ttf')); await loader.load();\n    final resources = await loadLayoutFixtureResources();")
s=s.replace('ThemeData(useMaterial3: true)',"ThemeData(useMaterial3: true,fontFamily:'Futura',colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff253759)).copyWith(surface:const Color(0xffebf1f6),surfaceContainer:const Color(0xffebf1f6),surfaceContainerLow:const Color(0xffebf1f6),surfaceContainerHigh:const Color(0xffebf1f6),surfaceContainerHighest:const Color(0xffebf1f6)),scaffoldBackgroundColor:const Color(0xffebf1f6))")
s=s[:s.index('VenueLayoutDocument captureInitialDocument')]+"VenueLayoutDocument captureInitialDocument(String id) => VenueLayoutDocument.fromJson(jsonDecode(r'''"+json.dumps(empty,ensure_ascii=False)+"'''));\n"
if a.resume_document:
 blank=json.loads(json.dumps(empty));blank['nodes']=[];blank['sections']=[]
 resume=json.loads(a.resume_document.read_text())
 if a.transparent_canvas:resume['canvas']['fill']='#00000000'
 if a.locale=='en':
  for n in resume['nodes']:
   if n.get('label','').startswith('Stůl '):n['label']='Table '+n['label'][5:]
   elif n.get('label')=='Pódium':n['label']='Stage'
   if n.get('text')=='Pódium':n['text']='Stage'
 marker='VenueLayoutDocument captureInitialDocument'
 s=s[:s.index(marker)]+"VenueLayoutDocument captureInitialDocument(String id) { final key=Uri.base.queryParameters['fixture']; final data=key=='blank' ? r'''"+json.dumps(blank,ensure_ascii=False)+"''' : key=='resume' ? r'''"+json.dumps(resume,ensure_ascii=False)+"''' : r'''"+json.dumps(empty,ensure_ascii=False)+"'''; return VenueLayoutDocument.fromJson(jsonDecode(data)); }\n"
if a.hide_canvas_controls:s=s.replace('VenueLayoutEditor(controller: controller)', 'VenueLayoutEditor(controller: controller, showCanvasControls:false)')
f.write_text(s)

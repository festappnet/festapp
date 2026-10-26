"""Prepare genuine text layouts for the exact palette factory output."""
import argparse,io,json,os,shutil,subprocess,tarfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('package',type=Path);p.add_argument('festapp',type=Path);p.add_argument('output',type=Path);p.add_argument('--locale',choices=['cs','en'],default='cs');p.add_argument('--brand-font',action='store_true');p.add_argument('--document',type=Path,action='append',default=[]);p.add_argument('--canonical-revision',default='8816cddc1bd9274deb794b5d795034c3aeec1650');a=p.parse_args()
work=a.output/'resource-preparation';work.mkdir(parents=True,exist_ok=True)
archive=subprocess.check_output(['git','-C',str(a.festapp),'archive',a.canonical_revision,'supabase/functions/_shared'])
with tarfile.open(fileobj=io.BytesIO(archive)) as tar:tar.extractall(work,filter='data')
shutil.copytree(a.package/'assets/layout_fonts',work/'assets/layout_fonts',dirs_exist_ok=True)
(work/'tool').mkdir(exist_ok=True);shutil.copy2(a.package/'tool/prepare_fixture_resources.ts',work/'tool/prepare_fixture_resources.ts')
target=a.output/'app/assets/packages/venue_seat_picker/assets/layout_fonts/fixtures.json'
# Extend the exact served corpus, retaining prior palette and locale requests.
if target.exists(): shutil.copy2(target,work/'assets/layout_fonts/fixtures.json')
resources=json.loads((work/'assets/layout_fonts/fixtures.json').read_text())
if a.brand_font:
    catalog=json.loads((work/'supabase/functions/_shared/ticket-assets/font-catalog.json').read_text())
    family=next(f for f in catalog['families'] if f['family']=='Futura PT')
    face=next(f for f in catalog['fonts'] if f['id']==family['faces']['400:normal'])
    resources['fontFamilies'][family['id']]=family
    (work/'assets/layout_fonts/fixtures.json').write_text(json.dumps(resources))
    manifest_path=work/'assets/layout_fonts/manifest.json';manifest=json.loads(manifest_path.read_text())
    manifest['fixtures'].append({'id':face['id'],'file':'Futura.ttf','family':'Futura PT','variant':'400:normal','sha256':face['sha256']})
    manifest_path.write_text(json.dumps(manifest))
    shutil.copy2(work/'supabase/functions/_shared/ticket-assets'/face['file'],work/'assets/layout_fonts/Futura.ttf')
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(work/'assets/layout_fonts/Futura.ttf',target.parent/'Futura.ttf')

(work/'catalog.json').write_text(json.dumps({'families':list(resources['fontFamilies'].values())}))
recipe=Path(__file__).resolve().parent
subprocess.run(['fvm','dart','--packages='+str(a.package/'.dart_tool/package_config.json'),str(recipe/'palette_requests.dart'),str(work/'catalog.json'),str(work/'palette-requests.json'),a.locale],cwd=a.festapp,check=True)
subprocess.run(['deno','run','--allow-read','--allow-write','--allow-env',str(work/'tool/prepare_fixture_resources.ts'),str(work/'supabase/functions/_shared'),str(work/'palette-requests.json')],check=True)
if a.document:
    subprocess.run(['fvm','dart','--packages='+str(a.package/'.dart_tool/package_config.json'),str(a.package/'tool/export_fixture_requests.dart'),str(work/'catalog.json'),str(work/'document-requests.json'),*[str(d.resolve()) for d in a.document]],cwd=a.festapp,check=True)
    subprocess.run(['deno','run','--allow-read','--allow-write','--allow-env',str(work/'tool/prepare_fixture_resources.ts'),str(work/'supabase/functions/_shared'),str(work/'document-requests.json')],check=True)
temporary=target.with_suffix('.json.new')
shutil.copy2(work/'assets/layout_fonts/fixtures.json',temporary)
os.replace(temporary,target)
print('Prepared actual Czech palette text resources in capture application')

"""Full decode and fingerprint localized clip exports and their posters."""
import argparse,hashlib,json,subprocess
from pathlib import Path
from urllib.parse import urlsplit
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument('--locale',choices=['cs','en'],default='cs');p.add_argument('--required-only',action='store_true');p.add_argument('--scenario-pairs',type=Path,help='Require reviewed CS/EN receipts for every rendered chapter');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
manifest=json.loads((a.root/('automation/release/organizers/clips.en.json' if a.locale=='en' else 'automation/release/organizers/clips.json')).read_text());rows=[];posters=[];required={manifest['hero']}|{i for s in manifest['sections'] for i in s['clips']}
def local(url):
 u=urlsplit(url);path=Path(u.path.lstrip('/'))
 if u.scheme or u.netloc or not u.path.startswith('/organizers-media/') or '..' in path.parts:raise ValueError('Only local organizer media is allowed')
 if a.locale=='en' and not u.path.startswith('/organizers-media/en/'):raise ValueError('English assets must not fall back to Czech')
 return a.root/'web'/path
for c in manifest['clips']:
 if a.required_only and c['id'] not in required:continue
 for key in ['src','mobileSrc']:
  f=local(c[key]);subprocess.run(['ffmpeg','-v','error','-i',str(f),'-f','null','-'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  q=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,duration','-of','json',str(f)],text=True))['streams'][0]
  mobile=key=='mobileSrc';prefix='mobile' if mobile else ''
  for field in ['width','height','duration']:
   expected=c[prefix+field[0].upper()+field[1:] if mobile else field]
   assert abs(float(q[field])-expected)<(.04 if field=='duration' else .01),(c['id'],key,field,q[field],expected)
  rows.append({'clip':c['id'],'variant':key,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size,'fullDecode':'pass',**q})
 for key in ['poster','mobilePoster']:
  f=local(c[key]);subprocess.run(['ffmpeg','-v','error','-i',str(f),'-frames:v','1','-f','null','-'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  posters.append({'clip':c['id'],'variant':key,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
for section in manifest['sections']:
 for item in section.get('showcase',{}).get('items',[]):
  f=local(item['image']);assert f.is_file(),f
  posters.append({'showcase':item['title'],'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
scenario_pairs=None
if a.scenario_pairs:
 from scenario_contract import verify_pairs
 scenario_pairs=verify_pairs(a.scenario_pairs,manifest)
 for match in scenario_pairs:
  hashes=match['enExportSha256' if a.locale=='en' else 'csExportSha256']
  for key,variant in [('desktop','src'),('mobile','mobileSrc')]:
   actual=next(r['sha256'] for r in rows if r['clip']==match['clip'] and r['variant']==variant)
   if actual!=hashes[key]:raise ValueError('Published media is not the reviewed scenario export: '+match['clip'])
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps({'locale':a.locale,'clips':rows,'postersAndStills':posters,'scenarioPairs':scenario_pairs,'scenarioParityChecked':scenario_pairs is not None},indent=2)+'\n');print(f'{len(rows)} variants fully decoded; dimensions, durations and posters match')

"""Full decode and fingerprint the current finalized clip manifest in one batch."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);p.add_argument('--output',type=Path,required=True);a=p.parse_args();manifest=json.loads((a.root/'automation/release/organizers/clips.json').read_text());rows=[]
for c in manifest['clips']:
 for key in ['src','mobileSrc']:
  f=a.root/'web'/c[key].lstrip('/');subprocess.run(['ffmpeg','-v','error','-i',str(f),'-f','null','-'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  q=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,duration','-of','json',str(f)],text=True))['streams'][0]
  expected=c['duration' if key=='src' else 'mobileDuration'];assert abs(float(q['duration'])-expected)<.04,(c['id'],key)
  rows.append({'clip':c['id'],'variant':key,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size,'fullDecode':'pass',**q})
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps({'locale':'cs','clips':rows},indent=2)+'\n');print(f'{len(rows)} variants fully decoded; durations match manifest')

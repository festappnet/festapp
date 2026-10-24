"""Builder-only edit, meal choices and required checkbox; actual recorded pixels."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);a=p.parse_args();r=a.root

def run(c):subprocess.run(c,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def enc(t,out,s,d,v):run(['python3',str(Path(__file__).with_name('encode.py')),str(t),str(out),'--start',str(s),'--end',str(s+d),'--filter',v])
t=next(r.glob('form-meal-final-cs-*'));b={x['name']:x['start'] for x in json.loads((t/'cues.json').read_text())};rt=next(r.glob('form-meal-result-cs-*'));rs=json.loads((rt/'cues.json').read_text())[0]['start']
segments=[('add-choice',0,3.2),('choice-title',0,2),('vegetarian',0,2.5),('meal-result',0,2.8),('add-checkbox',0,3.2),('checkbox-title',0,2.8),('required',0,2.2)]
for suffix,vf in [('', 'crop=1000:610:0:180,scale=1176:780:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=1200:804:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6'),('-mobile','crop=700:600:150:180,scale=696:614:force_original_aspect_ratio=decrease:force_divisible_by=2,pad=720:638:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6')]:
 parts=[]
 for i,(key,off,d) in enumerate(segments):
  o=r/f'builder-segment-{i}{suffix}.mp4';enc(t,o,b[key]+off,d,vf);parts.append(o)
 o=r/f'builder-result{suffix}.mp4';enc(rt,o,rs,3,vf);parts.append(o)
 listing=r/f'builder{suffix}.ffconcat';listing.write_text('\n'.join("file '"+str(x.resolve())+"'" for x in parts));out=r/f'form-build{suffix}.mp4'
 run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(listing),'-c','copy','-movflags','+faststart',str(out)])
 run(['ffmpeg','-y','-sseof','-0.3','-i',str(out),'-frames:v','1','-update','1',str(out.with_suffix('.jpg'))])
 run(['cwebp','-quiet','-q','92',str(out.with_suffix('.jpg')),'-o',str(out.with_suffix('.webp'))])
print('Builder exports ready')

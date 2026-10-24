"""Actual ticket product type and price editing; existing required field remains visible."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);a=p.parse_args();r=a.root;t=next(r.glob('form-priced-cs-*'));b={x['name']:x['start'] for x in json.loads((t/'cues.json').read_text())}
def run(c):subprocess.run(c,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
segments=[(t,b['add-product-group'],2),(t,b['group-title'],2),(t,b['chicken-name'],2),(t,b['chicken-price'],1.5),(t,b['add-vegetarian'],1.8),(t,b['vegetarian-name'],2),(t,b['vegetarian-price'],2.5),(t,b['result'],3.5)]
for suffix,w,h,crop,scale in [('',1200,804,'1000:610:0:180','1176:780'),('-mobile',720,638,'700:600:150:180','696:614')]:
 files=[]
 for i,(take,start,duration) in enumerate(segments):
  out=r/f'priced-{i}{suffix}.mp4';vf=f'crop={crop},scale={scale}:force_original_aspect_ratio=decrease:force_divisible_by=2,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6';run(['python3',str(Path(__file__).with_name('encode.py')),str(take),str(out),'--start',str(start),'--end',str(start+duration),'--filter',vf]);files.append(out)
 listing=r/f'priced{suffix}.ffconcat';listing.write_text('\n'.join("file '"+str(f.resolve())+"'" for f in files));out=r/f'form-build{suffix}.mp4';run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(listing),'-c','copy','-movflags','+faststart',str(out)])
 run(['ffmpeg','-y','-sseof','-0.3','-i',str(out),'-frames:v','1','-update','1',str(out.with_suffix('.jpg'))]);run(['cwebp','-quiet','-q','92',str(out.with_suffix('.jpg')),'-o',str(out.with_suffix('.webp'))])
print('Priced form exports ready')

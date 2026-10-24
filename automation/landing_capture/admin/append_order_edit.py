"""Append actual local order-note edit to preserved report overview; never recapture it."""
import argparse,json,subprocess,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('media',type=Path);a=p.parse_args();r=a.root;t=next(r.glob('order-note-cs-*'));b={x['name']:x['start'] for x in json.loads((t/'cues.json').read_text())}
def run(c):subprocess.run(c,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
for suffix,w,h in [('',1200,760),('-mobile',720,900)]:
 base=r/f'approved-overview{suffix}.mp4'
 if not base.exists():shutil.copy2(a.media/f'orders-overview{suffix}.mp4',base)
 files=[base]
 for i,(cue,dur) in enumerate([('edit-note',1.2),('type-note',1.6),('save-note',1.8),('saved',1.4)]):
  crop='crop=1100:600:0:140' if not suffix else ('crop=850:400:0:140' if cue=='save-note' else 'crop=500:400:450:140')
  vf=crop+f',scale={w}:{h}:force_original_aspect_ratio=decrease:force_divisible_by=2,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6'
  out=r/f'edit-{i}{suffix}.mp4';run(['python3',str(Path(__file__).with_name('encode.py')),str(t),str(out),'--start',str(b[cue]),'--end',str(b[cue]+dur),'--filter',vf]);files.append(out)
 listing=r/f'edit-joined{suffix}.ffconcat';listing.write_text('\n'.join("file '"+str(f.resolve())+"'" for f in files));out=r/f'orders-overview{suffix}.mp4';run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(listing),'-c','copy','-movflags','+faststart',str(out)])
 run(['ffmpeg','-y','-sseof','-0.3','-i',str(out),'-frames:v','1','-update','1',str(r/f'edit-proof{suffix}.jpg')])
 # Keep the previously approved Report lead poster.
 for ext in ['webp','jpg']:
  src=a.media/f'orders-overview{suffix}.{ext}'
  if src.exists():shutil.copy2(src,r/src.name)
print('Order-edit append ready')

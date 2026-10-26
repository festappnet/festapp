"""Export only valid report/customer-filter/export cues from the editable local copy."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('take',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(exist_ok=True,parents=True);c={x['name']:x for x in json.loads((a.take/'cues.json').read_text())}
def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
parts=[('report-summary',5.7,'report'),('orders-navigation',.9,'orders'),('orders-filter-final',4,'orders'),('ticket-export',2.5,'export')]
for suffix,w,h in [('',1200,760),('-mobile',720,900)]:
 files=[]
 for i,(cue,duration,kind) in enumerate(parts):
  if kind=='report':crop='crop=610:580:720:190' if suffix else 'crop=1440:912:0:0'
  elif kind=='export':crop='crop=850:250:250:100' if suffix else 'crop=1440:250:0:100'
  else:crop='crop=600:720:300:140' if suffix else 'crop=1440:912:0:0'
  vf=crop+f',scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0xf4f6fa';dest=a.output/f'editable-report-{i}{suffix}.mp4';files.append(dest);run(['python3',str(Path(__file__).with_name('encode.py')),str(a.take),str(dest),'--start',str(c[cue]['start']),'--end',str(c[cue]['start']+duration),'--filter',vf])
 f=a.output/f'editable-report{suffix}.ffconcat';f.write_text('\n'.join("file '"+str(x.resolve())+"'" for x in files));dest=a.output/('orders-overview'+suffix+'.mp4');run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(f),'-c','copy','-movflags','+faststart',str(dest)]);run(['ffmpeg','-y','-ss','0.7','-i',str(dest),'-frames:v','1','-update','1',str(dest.with_suffix('.png'))]);run(['cwebp','-quiet','-q','90',str(dest.with_suffix('.png')),'-o',str(dest.with_suffix('.webp'))])
print(a.output)

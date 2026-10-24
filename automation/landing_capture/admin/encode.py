"""Export a timestamped actual-UI take. No fabricated frames or motion."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('take',type=Path);p.add_argument('output',type=Path);p.add_argument('--filter',default='scale=1200:-2');p.add_argument('--start',type=float);p.add_argument('--end',type=float);a=p.parse_args()
f=json.loads((a.take/'frames.json').read_text());c=json.loads((a.take/'cues.json').read_text());start,end=a.start or c[0]['start'],a.end or c[-1]['end'];prior=[x for x in f if x['time']<start];frames=([dict(prior[-1],time=start)] if prior else [])+[x for x in f if start<=x['time']<=end];lines=[]
for i,x in enumerate(frames):
 duration=(frames[i+1]['time'] if i+1<len(frames) else end)-x['time']
 if duration>0:lines.extend([f"file '{a.take.resolve()/x['file']}'",'option framerate 1000',f'duration {duration:.6f}'])
lines.extend([f"file '{a.take.resolve()/frames[-1]['file']}'",'option framerate 1000']);manifest=a.take/'export.ffconcat';manifest.write_text('\n'.join(lines));a.output.parent.mkdir(parents=True,exist_ok=True)
def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(manifest),'-t',str(end-start),'-vf',a.filter+',fps=30,format=yuv420p','-an','-c:v','libx264','-crf','20','-preset','fast','-movflags','+faststart',str(a.output)])
run(['ffmpeg','-y','-sseof','-0.1','-i',str(a.output),'-frames:v','1','-update','1',str(a.output.with_suffix('.jpg'))]);print(a.output)

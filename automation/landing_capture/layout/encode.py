import json,subprocess,os
from pathlib import Path
ROOT=Path(os.environ['CAPTURE_DIR']).resolve()
MEDIA=Path(os.environ['MEDIA_DIR']).resolve();MEDIA.mkdir(parents=True,exist_ok=True)
def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def segment(directory,name,crop,duration=None,span=None):
 d=ROOT/directory;frames=json.loads((d/'frames.json').read_text());cues=json.loads((d/'cues.json').read_text());start,end=span or (cues[0]['start'],cues[-1]['end']);end=min(end,start+duration) if duration else end
 chosen=[f for f in frames if start<=f['time']<=end];prior=[f for f in frames if f['time']<start];chosen=([dict(prior[-1],time=start)] if prior else [])+chosen
 lines=[]
 for i,f in enumerate(chosen):
  delta=(chosen[i+1]['time'] if i+1<len(chosen) else end)-f['time']
  if delta>0:lines += [f"file '{d/f['file']}'",'option framerate 1000',f'duration {delta:.6f}']
 lines += [f"file '{d/chosen[-1]['file']}'","option framerate 1000"]
 concat=d/(name+'.txt');concat.write_text('\n'.join(lines));out=ROOT/(name+'.mp4')
 run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-t',str(end-start),'-vf',crop+',fps=30,format=yuv420p','-an','-c:v','libx264','-crf','20','-preset','fast','-movflags','+faststart',str(out)]);return out
def join(parts,name):
 concat=ROOT/(name+'-join.txt');concat.write_text('\n'.join(f"file '{p}'" for p in parts));out=MEDIA/(name+'.mp4')
 run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart',str(out)])
 run(['ffmpeg','-y','-sseof','-0.1','-i',str(out),'-frames:v','1','-update','1',str(MEDIA/(name+'.jpg'))]);return out

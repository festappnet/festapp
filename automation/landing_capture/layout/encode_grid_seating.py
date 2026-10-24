"""Compact genuine grid seating take. All acceleration declared by cue."""
import sys,json
from pathlib import Path
from encode_brand import manifest,run,probe
main,edges,out=map(Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=True);parts=[];proof=[]
for take,items in [(main,[('draw-first',1),('add-chairs',2),('second-table',1.5),('wood-source',1.5),('joint-style',1.5)]),(edges,[('extend-edge',1),('shrink-edge',1),('finished',1)])]:
 frames=json.loads((take/'frames.json').read_text());cues={c['name']:c for c in json.loads((take/'cues.json').read_text())}
 for name,speed in items:
  c=cues[name];start,end=c['start'],c['end']-.8
  if name=='finished':end=c['end'];start=end-1
  ff=out/(name+'.ffconcat');manifest(take,frames,start,end,ff);video=out/(name+'.mp4')
  run(['ffmpeg','-v','error','-y','-safe','0','-i',str(ff),'-vf',f'crop=1128:780:0:112,scale=in_range=full:out_range=limited,pad=1140:792:6:6:color=0xebf1f6,setpts=(PTS-STARTPTS)/{speed},fps=30,format=yuv420p','-t',str((end-start)/speed),'-c:v','libx264','-crf','19',str(video)])
  parts.append(video);proof.append(dict(name=name,source=str(take),start=start,end=end,speed=speed))
concat=out/'parts.txt';concat.write_text(''.join(f"file '{p.resolve()}'\n" for p in parts))
run(['ffmpeg','-v','error','-y','-safe','0','-f','concat','-i',str(concat),'-c','copy','-movflags','+faststart',str(out/'layout-grid.mp4')])
run(['ffmpeg','-v','error','-y','-i',str(out/'layout-grid.mp4'),'-vf','scale=820:-2,pad=820:792:0:(oh-ih)/2:color=0xebf1f6','-c:v','libx264','-crf','19','-movflags','+faststart',str(out/'layout-grid-mobile.mp4')])
for name in ['layout-grid','layout-grid-mobile']:
 stream,duration=probe(out/(name+'.mp4'));run(['ffmpeg','-v','error','-y','-sseof','-0.3','-i',str(out/(name+'.mp4')),'-frames:v','1',str(out/(name+'.jpg'))]);print(name,stream['width'],stream['height'],duration)
(out/'edit-proof.json').write_text(json.dumps(proof,indent=2))

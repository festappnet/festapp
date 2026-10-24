"""Prepend actual clear and append matching two-table backdrop to compact grid."""
import sys,json
from pathlib import Path
from encode_brand import manifest,run,probe
base,clear,backdrop,out=map(Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=True);parts=[];records=[]
def part(take,name,speed,tail=.8):
 frames=json.loads((take/'frames.json').read_text());c=next(c for c in json.loads((take/'cues.json').read_text()) if c['name']==name);start=c['start'];end=c['end']-tail
 if name=='finished':end=c['end'];start=end-1
 ff=out/(name+'.ffconcat');manifest(take,frames,start,end,ff);dest=out/(name+'.mp4')
 run(['ffmpeg','-v','error','-y','-safe','0','-i',str(ff),'-vf',f'crop=1128:780:0:112,scale=in_range=full:out_range=limited,pad=1140:792:6:6:color=0xebf1f6,setpts=(PTS-STARTPTS)/{speed},fps=30,format=yuv420p','-t',str((end-start)/speed),'-c:v','libx264','-crf','19',str(dest)])
 parts.append(dest);records.append(dict(name=name,source=str(take),start=start,end=end,speed=speed))
part(clear,'clear-hall',2)
parts += [base/(name+'.mp4') for name in ['draw-first','add-chairs','second-table','wood-source','joint-style','extend-edge','shrink-edge']]
for name in ['backdrop-insert','backdrop-resize','send-back']:part(backdrop,name,1.8)
part(backdrop,'finished',1)
f=out/'parts.txt';f.write_text(''.join(f"file '{p.resolve()}'\n" for p in parts));run(['ffmpeg','-v','error','-y','-safe','0','-f','concat','-i',str(f),'-c','copy','-movflags','+faststart',str(out/'layout-grid.mp4')])
run(['ffmpeg','-v','error','-y','-i',str(out/'layout-grid.mp4'),'-vf','scale=820:-2,pad=820:792:0:(oh-ih)/2:color=0xebf1f6','-c:v','libx264','-crf','19','-movflags','+faststart',str(out/'layout-grid-mobile.mp4')])
for name in ['layout-grid','layout-grid-mobile']:
 stream,duration=probe(out/(name+'.mp4'));run(['ffmpeg','-v','error','-y','-sseof','-0.3','-i',str(out/(name+'.mp4')),'-frames:v','1',str(out/(name+'.jpg'))]);run(['cwebp','-quiet','-q','92',str(out/(name+'.jpg')),'-o',str(out/(name+'.webp'))]);print(name,stream['width'],stream['height'],duration)
(out/'ending-proof.json').write_text(json.dumps(records,indent=2))

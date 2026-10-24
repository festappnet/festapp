"""Encode real clear/draw/edge/style/backdrop takes with full palette visible.
Arguments: CLEAR_TAKE GRID_TAKE BACKDROP_TAKE OUTPUT. No time compression.
"""
import sys,json
from pathlib import Path
from encode_brand import manifest,run,probe
clear,grid,backdrop,out=map(Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=True)
parts=[];records=[]
for take,names in [(clear,['clear-hall']),(grid,['empty','draw-table','extend-edge','shrink-edge','wood-style','warm-fill']),(backdrop,['backdrop-insert','backdrop-resize','send-back','backdrop-finished'])]:
 frames=json.loads((take/'frames.json').read_text());cues={c['name']:c for c in json.loads((take/'cues.json').read_text())}
 for name in names:
  c=cues[name];start,end=c['start'],c['end']
  if name=='empty':start=end-.6
  if name=='warm-fill':start=end-3.5 # omit idle/failed covered target before successful actual palette click
  ff=out/(name+'.ffconcat');manifest(take,frames,start,end,ff)
  video=out/(name+'.mp4')
  run(['ffmpeg','-v','error','-y','-safe','0','-i',str(ff),'-vf','crop=1128:780:0:112,scale=in_range=full:out_range=limited,pad=1140:792:6:6:color=0xebf1f6,fps=30,format=yuv420p','-t',str(end-start),'-c:v','libx264','-crf','19','-movflags','+faststart',str(video)])
  parts.append(video);records.append({'name':name,'source':str(take),'start':start,'end':end})
concat=out/'parts.txt';concat.write_text(''.join(f"file '{p.resolve()}'\n" for p in parts))
run(['ffmpeg','-v','error','-y','-safe','0','-f','concat','-i',str(concat),'-c','copy','-movflags','+faststart',str(out/'layout-grid.mp4')])
run(['ffmpeg','-v','error','-y','-i',str(out/'layout-grid.mp4'),'-vf','scale=820:-2,pad=820:792:0:(oh-ih)/2:color=0xebf1f6','-c:v','libx264','-crf','19','-movflags','+faststart',str(out/'layout-grid-mobile.mp4')])
for name in ['layout-grid','layout-grid-mobile']:
 stream,duration=probe(out/(name+'.mp4'));run(['ffmpeg','-v','error','-y','-sseof','-0.4','-i',str(out/(name+'.mp4')),'-frames:v','1',str(out/(name+'.jpg'))]);print(name,stream['width'],stream['height'],duration)
(out/'edit-proof.json').write_text(json.dumps(records,indent=2))

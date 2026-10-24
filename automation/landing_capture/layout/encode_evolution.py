"""Assemble genuine stage intro, complete clean build and separate refinement."""
import argparse,json
from pathlib import Path
from encode_clean import run,manifest,composition,probe,quoted
p=argparse.ArgumentParser();p.add_argument('root',type=Path);a=p.parse_args();r=a.root.resolve();out=r/'evolution-encoded';out.mkdir(exist_ok=True)
def cue_parts(take,names,prefix):
 frames=json.loads((take/'frames.json').read_text());cues={c['name']:c for c in json.loads((take/'cues.json').read_text())};parts=[]
 for i,(name,speed) in enumerate(names):
  c=cues[name];start,end=c['start'],c['end']
  if name not in ('blank-room','refined-hall'):end=max(start+.2,end-.8)
  if name=='blank-room':start=max(start,end-.6)
  f=out/f'{prefix}-{i}.ffconcat';manifest(take,frames,start,end,f);v=f.with_suffix('.mp4');run(['ffmpeg','-v','error','-y','-safe','0','-i',str(f),'-filter_complex',composition(name,speed),'-map','[out]','-t',str((end-start)/speed),'-an','-c:v','libx264','-crf','20','-preset','fast',str(v)]);parts.append(v)
 return parts
def latest(pattern):return sorted(r.glob(pattern))[-1]
def finish(name,parts):
 f=out/(name+'.ffconcat');f.write_text('\n'.join("file '"+quoted(v)+"'" for v in parts));v=out/(name+'.mp4');run(['ffmpeg','-v','error','-y','-safe','0','-f','concat','-i',str(f),'-c','copy','-movflags','+faststart',str(v)])
 if name=='layout-refine':
  from remove_copy_collision_frames import trim
  audit=[]
  for pattern,names in [('layout-refine-cs-*',[('select-middle',2),('delete-middle',1.5)]),('layout-refine-tail-cs-*',[('round-table',1.5),('round-chairs',1.35),('arc-reverse',1.35),('arc-forward',1.35),('refined-hall',1)])]:
   original={c['name']:c for c in json.loads((latest(pattern)/'cues.json').read_text())}
   for cue,speed in names:
    c=original[cue];audit.append(dict(cue=cue,encodedDuration=probe(out/(('refine-head' if pattern=='layout-refine-cs-*' else 'refine-tail')+'-'+str([n for n,_ in names].index(cue))+'.mp4'))[1]))
  (out/'round-transition-cuts.json').write_text(json.dumps(trim(v,audit,allowed_prefixes=('round-table',)),indent=2))
 m=out/(name+'-mobile.mp4');run(['ffmpeg','-v','error','-y','-i',str(v),'-vf','scale=820:792:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,pad=820:792:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,format=yuv420p','-c:v','libx264','-crf','20','-preset','fast','-movflags','+faststart',str(m)])
 for file in [v,m]:
  run(['ffmpeg','-v','error','-i',str(file),'-f','null','-']);run(['ffmpeg','-v','error','-y','-sseof','-0.2','-i',str(file),'-frames:v','1',str(file.with_suffix('.jpg'))]);run(['cwebp','-quiet','-q','92',str(file.with_suffix('.jpg')),'-o',str(file.with_suffix('.webp'))])
 print(name,probe(v)[1])
intro=cue_parts(latest('stage-intro-cs-*'),[('blank-room',1),('draw-stage',1.5),('name-stage',1.5),('surrounding-lines',4)],'intro')
finish('layout-build',intro+[r/'build-encoded/layout-build.mp4'])
head=cue_parts(latest('layout-refine-cs-*'),[('select-middle',2),('delete-middle',1.5)],'refine-head')
tail=cue_parts(latest('layout-refine-tail-cs-*'),[('round-table',1.5),('round-chairs',1.35),('arc-reverse',1.35),('arc-forward',1.35),('refined-hall',1)],'refine-tail')
finish('layout-refine',head+tail)
(out/'sources.json').write_text(json.dumps({'intro':str(latest('stage-intro-cs-*')),'build':str(r/'build-encoded'),'refineHead':str(latest('layout-refine-cs-*')),'refineTail':str(latest('layout-refine-tail-cs-*')),'composition':'continuous source crop, actual native UI; editorial cuts between actions; no pixel replacement'},indent=2))

"""Move archived genuine stage intro to the end of the editor playlist.
CORE INTRO_PART_DIRECTORY NEXT_BUILD OUTPUT. Honest cut to native empty-stage take;
last0.4s holds the actual next-build first frame to align the palette/scene junction.
"""
import sys,json,shutil
from pathlib import Path
from encode_clean import run,probe,quoted
core,intro,nxt,out=map(Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=True)
first=out/'next-first.png';run(['ffmpeg','-v','error','-y','-i',str(nxt),'-frames:v','1',str(first)])
hold=out/'ready-hold.mp4';run(['ffmpeg','-v','error','-y','-loop','1','-i',str(first),'-t','0.4','-r','30','-vf','format=yuv420p','-c:v','libx264','-crf','20',str(hold)])
parts=[core]+[intro/f'intro-{i}.mp4' for i in range(4)]+[hold]
f=out/'loop.ffconcat';f.write_text('\n'.join("file '"+quoted(p.resolve())+"'" for p in parts))
v=out/'layout-grid.mp4';run(['ffmpeg','-v','error','-y','-safe','0','-f','concat','-i',str(f),'-c','copy','-movflags','+faststart',str(v)])
m=out/'layout-grid-mobile.mp4';run(['ffmpeg','-v','error','-y','-i',str(v),'-vf','scale=820:792:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,pad=820:792:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,format=yuv420p','-c:v','libx264','-crf','20','-preset','fast','-movflags','+faststart',str(m)])
proof={'core':str(core),'coreDuration':probe(core)[1],'introParts':[str(p) for p in parts[1:5]],'transition':'honest editorial cut to archived empty-room native take; no simulated clear','junction':'0.4s editorial hold of actual next-build first frame; same stage/walls/full palette','outputs':{}}
for p in [v,m]:
 run(['ffmpeg','-v','error','-i',str(p),'-f','null','-'])
 run(['ffmpeg','-v','error','-y','-sseof','-0.1','-i',str(p),'-frames:v','1',str(out/(p.stem+'-loop-last.png'))])
 # Preserve the true mixed-table poster from the same unchanged core segment.
 for ext in ['jpg','webp']:shutil.copy2(core.parent/(p.stem+'.'+ext),out/(p.stem+'.'+ext))
 s,d=probe(p);proof['outputs'][p.name]={'width':s['width'],'height':s['height'],'duration':d,'decode':'PASS'}
(out/'loop-proof.json').write_text(json.dumps(proof,indent=2));print(json.dumps(proof['outputs']))

"""Constant editorial canvas; only genuine ticket pixels and native drags change."""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('showcase',type=Path);p.add_argument('drag',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
def run(c):subprocess.run(c,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
for suffix,w,h in [('',1200,822),('-mobile',900,720)]:
 parts=[]
 for i,name in enumerate(['drag']):
  out=a.output/f'canvas-{i}{suffix}.mp4';parts.append(out)
  cmd=['ffmpeg','-y']+(['-i',str(a.drag/'ticket-design.mp4')] if name=='drag' else ['-loop','1','-i',str(a.showcase/name),'-t','2'])
  vf=('crop=824:298:61:366,' if name=='drag' else '')+f'scale={w-80}:{h-80}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6,setsar=1,fps=30'
  if i>0:vf+=',fade=t=in:st=0:d=0.15:color=0xebf1f6'
  if name!='drag':vf+=',fade=t=out:st=1.85:d=0.15:color=0xebf1f6'
  run(cmd+['-vf',vf,'-an','-c:v','libx264','-crf','20','-pix_fmt','yuv420p',str(out)])
 manifest=a.output/f'ticket-canvas{suffix}.ffconcat';manifest.write_text('\n'.join("file '"+str(x.resolve())+"'" for x in parts));dest=a.output/('ticket-design'+suffix+'.mp4');run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(manifest),'-c','copy','-movflags','+faststart',str(dest)]);run(['ffmpeg','-y','-sseof','-0.1','-i',str(dest),'-frames:v','1','-update','1',str(dest.with_suffix('.jpg'))])
print(a.output)

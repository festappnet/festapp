"""Frame existing real narrow scanner footage as a symbolic phone (no UI edits)."""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
for suffix,width,height in [('',1200,800),('-mobile',720,1000)]:
 innerw,innerh=(334,700) if not suffix else (400,838)
 phonew,phoneh=innerw+32,innerh+60
 vf=f'scale={innerw}:{innerh},pad={phonew}:{phoneh}:16:30:color=0x151b28,drawbox=x={(phonew-52)//2}:y=12:w=52:h=5:color=0x7c8595:t=fill,drawbox=x={(phonew-70)//2}:y={phoneh-16}:w=70:h=4:color=0x7c8595:t=fill,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0xf4f6fa,setsar=1'
 out=a.output/f'check-in{suffix}.mp4'
 subprocess.run(['ffmpeg','-y','-i',str(a.source),'-vf',vf,'-c:v','libx264','-crf','19','-preset','fast','-movflags','+faststart','-an',str(out)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 subprocess.run(['ffmpeg','-y','-ss','2.1','-i',str(out),'-frames:v','1',str(out.with_suffix('.png'))],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 subprocess.run(['cwebp','-quiet','-q','90',str(out.with_suffix('.png')),'-o',str(out.with_suffix('.webp'))],check=True)
 print(out)

"""Editorially omit only transient Ctrl-copy overlap frames; never recolor UI.
The source duplicates in-place before pointer movement. Final layout is collision-free.
Every decoded frame is inspected in the canvas region. Only named copy cues may be cut.
"""
import json,subprocess
from pathlib import Path
def trim(video, cues, allowed_prefixes=('copy-',)):
 video=Path(video);height=int(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=height','-of','csv=p=0',str(video)]));roi=height-12;size=444*(roi//2)*3
 p=subprocess.Popen(['ffmpeg','-v','error','-i',str(video),'-vf',f'crop=888:{roi}:238:6,scale=444:{roi//2}','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
 hits=[];n=0
 while True:
  b=p.stdout.read(size)
  if len(b)!=size:break
  count=sum(1 for r,g,bb in zip(b[0::3],b[1::3],b[2::3]) if r>170 and g<105 and bb<105)
  if count>4:hits.append(n)
  n+=1
 assert p.wait()==0
 ranges=[];t=0
 for c in cues:
  if c['cue'].startswith(allowed_prefixes):ranges.append((t,t+c['encodedDuration']))
  t+=c['encodedDuration']
 assert all(any(a<=frame/30<b for a,b in ranges) for frame in hits),'Unexpected collision outside permitted editorial transition'
 if hits:
  target=video.with_name(video.stem+'-trimmed.mp4');expression='not('+ '+'.join('eq(n,'+str(i)+')' for i in hits)+')'
  subprocess.run(['ffmpeg','-v','error','-y','-i',str(video),'-vf',"select='"+expression+"',setpts=N/(30*TB)",'-an','-c:v','libx264','-crf','18','-preset','fast','-movflags','+faststart',str(target)],check=True);target.replace(video)
 return dict(sourceFrames=n,omittedCopyOverlapFrames=hits,method='Native transient-overlap frame cuts only in '+str(allowed_prefixes)+'; no pixel replacement; first palette drag and arc cues uncut')

"""Assemble chapter cues, removing setup pauses without speeding up input."""
import argparse,json,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);a=p.parse_args();script=Path(__file__).with_name('encode.py')
beats=[('form-build-cs-1792669322','add-text',3),('form-build-cs-1792669322','name-text',2.4),('form-build-cs-1792669322','add-select',2),('form-build-cs-1792669322','configure-select',2.5),('form-select-options-cs-1792669427','second-option',2.3),('form-build-cs-1792669322','add-checkbox',2),('form-build-cs-1792669322','checkbox-label',2.6),('form-build-cs-1792669322','required',2.4),('form-result-light-cs-1792669613','saved-public-result',2.5)]
for mobile in [False,True]:
 suffix='-mobile' if mobile else '';parts=[]
 for i,(directory,cue,duration) in enumerate(beats):
  d=a.root/directory;c=next(x for x in json.loads((d/'cues.json').read_text()) if x['name']==cue);out=a.root/f'form-part{i}{suffix}.mp4';parts.append(out)
  size='720:900' if mobile else '1200:760';crop='crop=700:800:370:180' if mobile else 'crop=1000:900:220:80'
  if 'result' in directory:crop='crop=680:760:380:0' if mobile else 'crop=1000:900:220:0'
  vf=crop+f',scale={size}:force_original_aspect_ratio=decrease,pad={size}:(ow-iw)/2:(oh-ih)/2:color=0xf4f6fa'
  subprocess.run([sys.executable,str(script),str(d),str(out),'--start',str(c['start']),'--end',str(c['start']+duration),'--filter',vf],check=True,stdout=subprocess.DEVNULL)
 manifest=a.root/f'form-join{suffix}.ffconcat';manifest.write_text('\n'.join(f"file '{x.resolve()}'" for x in parts));out=a.root/f'form-build{suffix}.mp4'
 subprocess.run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(manifest),'-c','copy','-movflags','+faststart',str(out)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 subprocess.run(['ffmpeg','-y','-sseof','-0.1','-i',str(out),'-frames:v','1',str(out.with_suffix('.jpg'))],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE);print(out)

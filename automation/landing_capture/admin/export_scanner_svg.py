"""Export direct-on-navy Chromium SVG composition; no pixel key/replacement."""
import argparse,json,subprocess,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('media',type=Path);a=p.parse_args();recipe=Path(__file__).parent;proof=[]
def run(args):return subprocess.run(args,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
for variant,w,h,suffix in [('desktop',1200,800,''),('mobile',500,1000,'-mobile')]:
 take=sorted(a.root.glob('iphone-svg-'+variant+'-*'))[-1];cue=json.loads((take/'cues.json').read_text())[0];out=a.media/('check-in'+suffix+'.mp4')
 run(['python3',str(recipe/'encode.py'),str(take),str(out),'--filter',f'scale={w}:{h}:flags=lanczos','--start',str(cue['start']),'--end',str(cue['start']+8.5)])
 for label,t in [('accepted',3.4),('rejected',6.4)]:
  frame=a.root/(variant+'-'+label+'.png');run(['ffmpeg','-v','error','-y','-ss',str(t),'-i',str(out),'-frames:v','1',str(frame)])
  crop='crop=160:150:170:845' if variant=='mobile' else 'crop=210:260:705:265'
  run(['ffmpeg','-v','error','-y','-i',str(frame),'-vf',crop,'-frames:v','1',str(a.root/(variant+'-'+label+'-close.png'))])
 run(['ffmpeg','-v','error','-y','-ss','3.4','-i',str(out),'-frames:v','1','-update','1',str(out.with_suffix('.jpg'))])
 run(['ffmpeg','-v','error','-i',str(out),'-f','null','-']);run(['ffmpeg','-v','error','-i',str(out.with_suffix('.jpg')),'-f','null','-'])
 rgb=run(['ffmpeg','-v','error','-i',str(out),'-vf','select=eq(n\\,0),format=rgb24,crop=1:1:0:0','-frames:v','1','-f','rawvideo','-'])
 probe=json.loads(run(['ffprobe','-v','error','-show_entries','stream=width,height:format=duration','-of','json',str(out)]));assert probe['streams'][0]['width']==w and probe['streams'][0]['height']==h;assert abs(float(probe['format']['duration'])-8.5)<.001
 proof.append({'asset':str(out),'take':str(take),'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'configuredMatte':'#19243b','decodedEdgeRGB':list(rgb),'width':w,'height':h,'duration':8.5,'decode':'pass','posterDecode':'pass'})
(a.root/'svg-export-proof.json').write_text(json.dumps(proof,indent=2)+'\n');print('Two SVG-composed MP4s and accepted posters decoded successfully')

"""Export recorded editorial scanner composition, retaining outcome timestamps."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);a=p.parse_args();r=a.root
for kind,suffix in [('desktop',''),('mobile','-mobile')]:
 t=next(r.glob('iphone-scanner-'+kind+'-cs-*'));start=json.loads((t/'cues.json').read_text())[0]['start'];out=r/('check-in'+suffix+'.mp4')
 subprocess.run(['python3',str(Path(__file__).with_name('encode.py')),str(t),str(out),'--end',str(start+8.5),'--filter','scale=iw:ih,tpad=stop_mode=clone:stop_duration=0.15'],check=True)
 subprocess.run(['ffmpeg','-v','error','-y','-ss','3.3','-i',str(out),'-frames:v','1','-update','1',str(out.with_suffix('.jpg'))],check=True)
 subprocess.run(['cwebp','-quiet','-q','92',str(out.with_suffix('.jpg')),'-o',str(out.with_suffix('.webp'))],check=True)

"""Export the actual themed form creation and matching result. Inputs are outside Git; no generated UI frames."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(exist_ok=True,parents=True)
def run(c):subprocess.run(c,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def encode(take,out,start,end,vf):run(['python3',str(Path(__file__).with_name('encode.py')),str(take),str(out),'--start',str(start),'--end',str(end),'--filter',vf])
def join(parts,out):
 f=out.with_suffix('.ffconcat');f.write_text('\n'.join("file '"+str(x.resolve())+"'" for x in parts));run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(f),'-c','copy','-movflags','+faststart',str(out)]);run(['ffmpeg','-y','-sseof','-0.1','-i',str(out),'-frames:v','1','-update','1',str(out.with_suffix('.jpg'))])
take=next(a.root.glob('form-theme-final-cs-*'));c=json.loads((take/'cues.json').read_text());b={x['name']:x['start'] for x in c}
result_take=next(a.root.glob('form-public-final-cs-*'));result_start=json.loads((result_take/'cues.json').read_text())[0]['start']
def result_filter(suffix):return 'crop=700:280:150:160,scale='+('1200:480,pad=1200:804:0:162:color=0xeff1f3' if not suffix else '720:288,pad=720:638:0:175:color=0xeff1f3')
segments=[('add-text',0,2.5),('text-title',0,1.6),('add-choice',0,2.4),('choice-title',0,2.4),('add-checkbox',-1,3.3),('checkbox-title',0,2.8),('required',0,2),('save',0,2.5)]
for suffix,vf in [('', 'crop=1000:670:0:180,scale=1200:804'),('-mobile','crop=700:620:150:180,scale=720:638')]:
 parts=[]
 for i,(name,offset,duration) in enumerate(segments):
  out=a.output/f'field-{i}{suffix}.mp4';encode(take,out,b[name]+offset,b[name]+offset+duration,vf);parts.append(out)
 # Public result: focus on the three authored fields, excluding unrelated ticket selector.
 out=a.output/f'field-result{suffix}.mp4';encode(result_take,out,result_start+2,result_start+5,result_filter(suffix));parts.append(out);join(parts,a.output/('form-build'+suffix+'.mp4'))
for suffix in ['', '-mobile']:
 run(['ffmpeg','-y','-ss','8','-i',str(a.output/('form-build'+suffix+'.mp4')),'-frames:v','1','-update','1',str(a.output/('form-build'+suffix+'.jpg'))])
for suffix in ['', '-mobile']:
 out=a.output/('form-style'+suffix+'.mp4');encode(result_take,out,result_start,result_start+5,result_filter(suffix))
print(a.output)

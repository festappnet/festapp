"""Export genuine preset/form takes. Inputs are outside Git; no generated UI frames."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('drag',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(exist_ok=True,parents=True)
def run(c):subprocess.run(c,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def encode(take,out,start,end,vf):run(['python3',str(Path(__file__).with_name('encode.py')),str(take),str(out),'--start',str(start),'--end',str(end),'--filter',vf])
def join(parts,out):
 f=out.with_suffix('.ffconcat');f.write_text('\n'.join("file '"+str(x.resolve())+"'" for x in parts));run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(f),'-c','copy','-movflags','+faststart',str(out)]);run(['ffmpeg','-y','-sseof','-0.1','-i',str(out),'-frames:v','1','-update','1',str(out.with_suffix('.jpg'))])
for source,name,crop in [('gala','ball','354:810:503:170'),('club','concert','920:308:220:421'),('theatre','theatre','576:810:392:170')]:run(['ffmpeg','-y','-i',str(a.root/(source+'.png')),'-vf','crop='+crop,'-frames:v','1','-update','1','-q:v','2',str(a.output/('ticket-'+name+'.jpg'))])
take=next(a.root.glob('ticket-variants-cs-*'));c=json.loads((take/'cues.json').read_text())
for suffix,vf in [('', 'crop=1240:850:200:0,scale=1200:822'),('-mobile','crop=1000:800:200:120,scale=900:720')]:
 parts=[]
 for i,beat in enumerate([c[1],c[3],c[5]]):
  out=a.output/f'preset-{i}{suffix}.mp4';encode(take,out,beat['start']+.2,beat['start']+2.2,vf);parts.append(out)
 # Retain all original native text + QR gestures, with same output dimensions.
 drag=a.output/f'drag{suffix}.mp4';run(['ffmpeg','-y','-i',str(a.drag/('ticket-design'+suffix+'.mp4')),'-vf',('scale=1200:822' if not suffix else 'scale=900:720'),'-c:v','libx264','-crf','20','-pix_fmt','yuv420p','-an',str(drag)]);parts.append(drag);join(parts,a.output/('ticket-design'+suffix+'.mp4'))
take=next(a.root.glob('form-clear-cs-*'));c=json.loads((take/'cues.json').read_text());b={x['name']:x['start'] for x in c}
segments=[('add-text',0,2.5),('text-title',0,1.6),('add-choice',0,2.4),('choice-title',0,2.4),('add-checkbox',-1,3.3),('checkbox-title',0,2.8),('required',0,2),('save',0,2.5)]
for suffix,vf in [('', 'crop=1000:670:0:180,scale=1200:804'),('-mobile','crop=700:620:150:180,scale=720:638')]:
 parts=[]
 for i,(name,offset,duration) in enumerate(segments):
  out=a.output/f'field-{i}{suffix}.mp4';encode(take,out,b[name]+offset,b[name]+offset+duration,vf);parts.append(out)
 # Public result: focus on the three authored fields, excluding unrelated ticket selector.
 out=a.output/f'field-result{suffix}.mp4';encode(take,out,b['result']+1.5,b['result']+4.5,'crop=700:310:150:170,scale='+('1200:532,pad=1200:804:0:136:color=0xe6e5d5' if not suffix else '720:318,pad=720:638:0:160:color=0xe6e5d5'));parts.append(out);join(parts,a.output/('form-build'+suffix+'.mp4'))
for suffix in ['', '-mobile']:
 run(['ffmpeg','-y','-ss','8','-i',str(a.output/('form-build'+suffix+'.mp4')),'-frames:v','1','-update','1',str(a.output/('form-build'+suffix+'.jpg'))])
print(a.output)

"""Real report -> same occasion orders -> real ticket CSV export, native cadence."""
import argparse,json,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('take',type=Path);p.add_argument('legacy',type=Path);p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);encoder=Path(__file__).with_name('encode.py')
c={x['name']:x for x in json.loads((a.take/'cues.json').read_text())};export=a.legacy/'orders-export-final-frames';ec=json.loads((a.legacy/'orders-export-final-cue.json').read_text());(export/'cues.json').write_text(json.dumps([dict(name='ticket-csv-export',**ec)]))
parts=[(a.take,c['report-summary']['start'],c['report-summary']['start']+5.7,'report'),(a.take,c['orders-navigation']['start'],c['orders-navigation']['start']+.9,'orders'),(a.take,c['orders-filter']['start'],c['orders-filter']['end'],'orders'),(export,ec['start'],ec['end'],'export')]
for mobile in [False,True]:
 suffix='-mobile' if mobile else '';size='720:900' if mobile else '1200:760';outs=[]
 for i,(take,start,end,kind) in enumerate(parts):
  if kind=='report':crop='crop=610:580:720:225' if mobile else 'crop=1440:912:0:0'
  elif kind=='export':crop='crop=600:666:0:50' if mobile else 'crop=820:520:0:45'
  else:crop='crop=600:720:260:150' if mobile else 'crop=1440:912:0:0'
  vf=crop+f',scale={size}:force_original_aspect_ratio=decrease,pad={size}:(ow-iw)/2:(oh-ih)/2:color=0xf4f6fa'
  out=a.output/f'report-orders-part{i}{suffix}.mp4';outs.append(out);subprocess.run([sys.executable,str(encoder),str(take),str(out),'--start',str(start),'--end',str(end),'--filter',vf],check=True,stdout=subprocess.DEVNULL)
 manifest=a.output/f'report-orders{suffix}.ffconcat';manifest.write_text('\n'.join(f"file '{f.resolve()}'" for f in outs));out=a.output/f'orders-overview{suffix}.mp4'
 subprocess.run(['ffmpeg','-v','error','-y','-f','concat','-safe','0','-i',str(manifest),'-c','copy','-movflags','+faststart',str(out)],check=True)
 subprocess.run(['ffmpeg','-v','error','-y','-ss','0.7','-i',str(out),'-frames:v','1',str(out.with_suffix('.png'))],check=True)
 subprocess.run(['cwebp','-quiet','-q','90',str(out.with_suffix('.png')),'-o',str(out.with_suffix('.webp'))],check=True);print(out)

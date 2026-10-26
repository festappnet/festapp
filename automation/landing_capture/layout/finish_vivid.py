from encode import *
run(['ffmpeg','-y','-i',str(ROOT/'hall-final.png'),'-vf','crop=892:716:250:168,scale=860:690','-frames:v','1','-q:v','2',str(MEDIA/'hero-hall.jpg')])
for kind in ['build','style']:
 take=sorted(ROOT.glob('layout-'+kind+'-cs-*'))[-1]
 for mobile in [False,True]:
  suffix='-mobile' if mobile else '';scale='720:900' if mobile else '1200:760'
  parts=[]
  for i,cue in enumerate(json.loads((take/'cues.json').read_text())):
   crop='crop=1140:824:0:114' if cue['name']=='palette-table' else ('crop=1000:650:440:290' if cue['name'] in ['add-chairs','copy-second-table','color-zones'] else 'crop=892:716:250:168')
   fit=crop+f',scale={scale}:force_original_aspect_ratio=decrease,pad={scale}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6'
   parts.append(segment(take.name,kind+'-'+str(i)+suffix,fit,span=(cue['start'],cue['end'])))
  join(parts,'layout-'+kind+suffix)
print('Vivid actual editor exports ready')

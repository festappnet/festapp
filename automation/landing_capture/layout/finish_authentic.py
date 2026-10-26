from encode import *
for kind in ['build','style']:
 take=sorted(ROOT.glob('layout-'+kind+'-cs-*'))[-1]
 for mobile in [False,True]:
  suffix='-mobile' if mobile else '';scale='820:824' if mobile else '1140:824';parts=[]
  for i,cue in enumerate(json.loads((take/'cues.json').read_text())):
   if cue['name']=='conference':continue
   # No inspector enters either editorial crop. The actual left palette remains
   # visible during both genuine drags. Finished plans use the full real canvas.
   crop=('crop=820:824:0:114' if mobile else 'crop=1140:824:0:114') if kind=='build' and cue['name']!='finished-edit' else 'crop=924:824:234:114'
   fit=crop+f',scale={scale}:force_original_aspect_ratio=decrease,pad={scale}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6'
   parts.append(segment(take.name,kind+'-'+str(i)+suffix,fit,span=(cue['start'],cue['end'])))
  join(parts,'layout-'+kind+suffix)
  run(['ffmpeg','-y','-ss',('1.5' if kind=='build' else '4.5'),'-i',str(MEDIA/('layout-'+kind+suffix+'.mp4')),'-frames:v','1','-update','1',str(MEDIA/('layout-'+kind+suffix+'.jpg'))])
for name in ['cinema','theatre','scout']:
 run(['ffmpeg','-y','-i',str(ROOT/(name+'.png')),'-vf','crop=924:824:234:114','-frames:v','1','-q:v','2',str(MEDIA/('layout-'+name+'.jpg'))])
print('Authentic templates exported; no hero changed')

from encode import *
for name in ['cinema','theatre','conference']:
 run(['ffmpeg','-y','-i',str(ROOT/(name+'.png')),'-vf','crop=924:824:234:114','-frames:v','1','-q:v','2',str(MEDIA/('layout-'+name+'.jpg'))])
run(['ffmpeg','-y','-i',str(ROOT/'hall-complete.png'),'-vf','crop=924:824:234:114,scale=860:768','-frames:v','1','-q:v','2',str(MEDIA/'hero-hall.jpg')])
build=sorted(ROOT.glob('layout-build-cs-*'))[-1];style=sorted(ROOT.glob('layout-style-cs-*'))[-1]
for mobile in [False,True]:
 suffix='-mobile' if mobile else '';scale='720:900' if mobile else '1200:760'
 fit=lambda c:c+f',scale={scale}:force_original_aspect_ratio=decrease,pad={scale}:(ow-iw)/2:(oh-ih)/2:color=0xebf1f6'
 cues=json.loads((build/'cues.json').read_text());parts=[]
 for i,cue in enumerate(cues):
  crop='crop=1140:824:0:114' if cue['name']=='palette-table' else ('crop=1000:650:440:290' if cue['name']!='complete-hall' else 'crop=924:824:234:114')
  parts.append(segment(build.name,'build-'+str(i)+suffix,fit(crop),span=(cue['start'],cue['end'])))
 join(parts,'layout-build'+suffix)
 cues=json.loads((style/'cues.json').read_text());parts=[]
 for i,cue in enumerate(cues):
  crop='crop=1040:650:400:290' if i==0 else 'crop=924:824:234:114'
  span=(cue['start'],cue['end']) if i==0 else (cue['end']-2.5,cue['end'])
  parts.append(segment(style.name,'style-'+str(i)+suffix,fit(crop),span=span))
 join(parts,'layout-style'+suffix)
print('Encoded Czech layout clips and gallery.')

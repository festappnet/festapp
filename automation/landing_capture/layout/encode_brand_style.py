"""Real Futura hall and two existing template previews; no application chrome."""
from encode import *
build=sorted(ROOT.glob('layout-build-cs-*'))[-1];templates=sorted(ROOT.glob('layout-style-templates-cs-*'))[-1]
b=next(c for c in json.loads((build/'cues.json').read_text()) if c['name']=='finished-hall');t=json.loads((templates/'cues.json').read_text())
for mobile in (False,True):
 name='layout-style'+('-mobile' if mobile else '');crop='crop=924:800:234:128,pad=1140:824:108:12:color=0xebf1f6'
 if mobile:crop+=',scale=820:-2,pad=820:824:0:(oh-ih)/2:color=0xebf1f6'
 parts=[segment(build.name,name+'-hall',crop,span=(b['start'],b['end']))]
 parts += [segment(templates.name,name+'-'+c['name'],crop,span=(c['start'],c['end'])) for c in t]
 join(parts,name)
 run(['ffmpeg','-y','-i',str(ROOT/'hall-complete.png'),'-vf',crop,'-frames:v','1','-update','1',str(MEDIA/(name+'.jpg'))])
for source,name,rect in [('hall-complete','scout','crop=715:715:338:168'),('cinema-red','cinema','crop=820:760:286:128'),('theatre','theatre','crop=794:760:299:128')]:
 run(['ffmpeg','-y','-i',str(ROOT/(source+'.png')),'-vf',rect,'-frames:v','1','-update','1',str(MEDIA/('layout-'+name+'.jpg'))])

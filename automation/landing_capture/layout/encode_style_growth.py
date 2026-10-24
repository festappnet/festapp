"""Edit only real global-colour actions and genuine template results."""
from encode import *
d=sorted(ROOT.glob('layout-style-cs-*'))[-1];cues=json.loads((d/'cues.json').read_text())
for mobile in (False,True):
 name='layout-style'+('-mobile' if mobile else '');parts=[]
 crop='crop=1140:824:0:114'
 if mobile:crop+=',scale=820:-2,pad=820:824:0:(oh-ih)/2:color=0xebf1f6'
 for cue in cues:
  # Remove navigation between global controls, keeping action + immediate result.
  parts.append(segment(d.name,name+'-'+cue['name'],crop,span=(cue['start'],cue['end'])))
 out=join(parts,name)
 # Clean final blue hall, rather than a dialog, represents this chapter.
 run(['ffmpeg','-y','-i',str(ROOT/'restyled-hall.png'),'-vf',crop,'-frames:v','1','-update','1',str(MEDIA/(name+'.jpg'))])

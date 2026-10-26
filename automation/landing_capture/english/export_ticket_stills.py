"""Convert canonical English preset PDFs to landing stills on the capture Mac."""
from pathlib import Path
import argparse,subprocess,json
p=argparse.ArgumentParser();p.add_argument('pdf_directory',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[3];out=root/'web/organizers-media/en'
names={'ball_silk':('ticket-ball','Ball invitation'),'concert_stub':('ticket-concert','Concert stub'),'theatre_program':('ticket-theatre','Theatre programme'),'boarding_pass':('ticket-showcase-boarding-pass','Boarding pass'),'cinema_strip':('ticket-showcase-cinema-strip','Cinema strip'),'gallery_square':('ticket-showcase-gallery-square','Gallery square'),'sports_arena':('ticket-showcase-sports-arena','Sports arena'),'workshop_card':('ticket-showcase-workshop-card','Workshop card')}
m=root/'automation/release/organizers/clips.en.json';manifest=json.loads(m.read_text());items=manifest['sections'][2]['showcase']['items']
for item,(key,(name,title)) in zip(items,names.items()):
 png=a.pdf_directory/(key+'.png');subprocess.run(['sips','-s','format','png',str(a.pdf_directory/(key+'.pdf')),'--out',str(png)],check=True,stdout=subprocess.DEVNULL)
 target=out/(name+('.jpg' if not name.startswith('ticket-showcase') else '.webp'))
 command=['cwebp','-quiet','-q','88','-resize','1200','0',str(png),'-o',str(target)] if target.suffix=='.webp' else ['ffmpeg','-v','error','-y','-i',str(png),'-vf','scale=1200:-2',str(target)]
 subprocess.run(command,check=True);q=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=width,height','-of','json',str(target)]))['streams'][0]
 item.update(title=title,description='An English sample from the shared ticket designer.',image='/organizers-media/en/'+target.name,alt=title+' with English event and guest details',width=q['width'],height=q['height'])
m.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print('Eight English ticket stills exported')

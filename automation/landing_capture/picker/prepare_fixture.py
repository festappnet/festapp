"""Adapt the existing scout-ball-182 reference geometry into a disposable Festapp blueprint."""
import json, os
locale=os.environ.get("CAPTURE_LOCALE", "cs")
if locale not in ("cs","en"): raise ValueError("Supported fixture locales: cs, en")
from pathlib import Path
import re, hashlib
package=Path(os.environ['LAYOUT_PACKAGE'])
source=package/'lib/src/templates/scout_reference_data.dart'
raw=source.read_text()
def rows(name):
    block=raw.split('const '+name+' =',1)[1].split('[',1)[1].split('];',1)[0]
    return re.findall(r'\(([^)]+)\)',block)
tables=[tuple(float(v.strip()) for v in row.split(',')) for row in rows('scoutTables')]
architecture=[]
for row in rows('scoutArchitecture'):
    values=row.split(',');architecture.append((values[0].strip().strip('"'),*[float(v) for v in values[1:]]))
seats=[]
for row in rows('scoutSeats'):
    g,label,x,y=row.split(',');seats.append((int(g),label.strip().strip('"'),int(x),int(y)))
if os.environ.get('CAPTURE_PROVENANCE'):
    Path(os.environ['CAPTURE_PROVENANCE']).write_text(json.dumps({'template':'scout-ball-182','source':'lib/src/templates/scout_reference_data.dart','sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),'seatCount':len(seats),'tableCount':len(tables),'lattice':[32,32],'adapter':'original integer seat coordinates and original SVG table/architecture bounds; original coordinates divided by 100 implicitly through 3200 viewBox/32 grid'},indent=2))
objects=[dict(id=421+i,type='spot',group=g,title=label,x=x,y=y) for i,(g,label,x,y) in enumerate(seats)]
assert len(objects)==182 and len({(o['x'],o['y']) for o in objects})==182
svg=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 3200 3200">']
for name,x0,y0,x1,y1 in architecture:
    color='#ffffff' if name=='room' else '#8da5ff' if name.startswith('column') else '#e6e6e6'
    svg.append(f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" fill="{color}" stroke="#000" stroke-width="5"/>')
    if name.startswith('column'):
        svg.append(f'<path d="M{x0} {y0}L{x1} {y1}M{x0} {y1}L{x1} {y0}" stroke="#000" stroke-width="5"/>')
    label='Pódium' if name=='stage' else 'vstup' if name=='entry' else 'sloup' if name.startswith('column') else ''
    if label:
        size=100 if name=='stage' else 44
        y=(y0+y1)/2 if not name.startswith('column') else y0-30
        svg.append(f'<text x="{(x0+x1)/2}" y="{y}" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-size="{size}">{label}</text>')
for group,x0,y0,x1,y1 in tables:
    svg.append(f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" fill="#fff" stroke="#000" stroke-width="5"/><text x="{(x0+x1)/2}" y="{(y0+y1)/2}" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-size="48">{int(group)}</text>')
svg.append('<text x="1460" y="1250" text-anchor="middle" dominant-baseline="central" font-family="sans-serif" font-size="136">Taneční parket</text></svg>')
if locale=='en':
    for old,new in [('Pódium','Stage'),('vstup','entrance'),('sloup','column'),('Taneční parket','Dance floor')]: svg=[part.replace(old,new) for part in svg]
def literal(v): return "'"+v.replace("'","''")+"'"
print("BEGIN; DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=6 AND title IN ('Ples pod hvězdami','Ball under the stars')) THEN RAISE EXCEPTION 'Synthetic fixture missing'; END IF; END $$;")
print("UPDATE eshop.blueprints SET objects="+literal(json.dumps(objects))+"::jsonb, configuration='{\"dimensions\":{\"width\":32,\"height\":32}}',background_svg="+literal(''.join(svg))+" WHERE id=3 AND occasion=6;")
print("INSERT INTO form_fields(title,type,is_required,form,is_ticket_field,\"order\") SELECT 'Místo v sále','spot',true,7,true,3 WHERE NOT EXISTS(SELECT 1 FROM form_fields WHERE form=7 AND type='spot');")

print("UPDATE public.forms SET data=data #- '{design,font_family}', header='<p>Vyberte si místo v sále.</p>' WHERE id=7 AND occasion=6;")

if locale=='en':
    print("UPDATE public.occasions SET title='Ball under the stars' WHERE id=6; UPDATE public.forms SET title='Ball under the stars',header='<p>Choose your seats. Tables 1-5: CZK650, remaining tables: CZK450. All information is fictional.</p>' WHERE id=7;")
    labels={'Kontaktní email':'Contact email','Místo v sále':'Seat','Vstupenka':'Ticket','Jméno':'First name','Příjmení':'Last name','Vstupné':'Admission','Večeře':'Dinner'}
    for original,translated in labels.items(): print('UPDATE public.form_fields SET title='+literal(translated)+' WHERE form=7 AND title='+literal(original)+';')
    print("UPDATE public.form_fields SET data='{\"options\":[{\"value\":\"Chicken menu\"},{\"value\":\"Vegetarian menu\"}]}'::jsonb WHERE form=7 AND type='select_one';")
    print("UPDATE eshop.products SET title=replace(replace(title,'Vstupné u pódia - stoly 1-5','Admission near the stage - tables 1-5'),'Základní vstupné','Standard admission') WHERE occasion=6;")
    print("UPDATE eshop.blueprints SET groups=(SELECT jsonb_agg(jsonb_set(g,'{title}',to_jsonb(replace(g->>'title','Stůl ','Table ')))) FROM jsonb_array_elements(groups) g) WHERE id=3;")
print("UPDATE eshop.blueprints SET groups="+literal(json.dumps([dict(id=i,title=('Stůl ' if locale=='cs' else 'Table ')+str(i)) for i in range(1,32)]))+"::jsonb WHERE id=3;")
for i,(g,label,x,y) in enumerate(seats):
    print(f"UPDATE eshop.spots SET title={literal(label)}, product={8 if g<=5 else 7} WHERE id={421+i} AND blueprint=3 AND occasion=6;")
print("UPDATE public.form_fields SET is_ticket_field=false, title=CASE type WHEN 'name' THEN 'Kontaktní jméno' ELSE 'Kontaktní příjmení' END, \"order\"=CASE type WHEN 'name' THEN 1 ELSE 2 END WHERE form=7 AND type IN ('name','surname');")
print("UPDATE public.form_fields SET \"order\"=0 WHERE form=7 AND type='email'; UPDATE public.form_fields SET \"order\"=3 WHERE form=7 AND type='ticket';")
if locale=='en':
    print("UPDATE public.form_fields SET title=CASE type WHEN 'name' THEN 'Contact first name' ELSE 'Contact last name' END WHERE form=7 AND type IN ('name','surname');")
print("UPDATE public.forms SET data=jsonb_set(jsonb_set(data, '{design,primary_color}', '\"#FF253759\"'), '{design,secondary_color}', '\"#FFEBF1F6\"') WHERE id=7 AND occasion=6;")
print("COMMIT;")

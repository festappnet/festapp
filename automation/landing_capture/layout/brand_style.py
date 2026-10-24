family='font-family:1ad255e344dade3427a6baaaf48aaaca6b18061a7476c73ebd27d8966dd37ea3'
def brand(d):
 label={'fontFamilyId':family,'weight':400,'color':'#253759FF'}
 kinds=d.setdefault('styles',{}).setdefault('kinds',{})
 d['styles']['label']={**d['styles'].get('label',{}),**label}
 kinds['table']={**kinds.get('table',{}),'fill':'#80BDF2FF','stroke':'#253759FF','strokeWidth':3,'label':{**kinds.get('table',{}).get('label',{}),**label}}
 kinds['seat']={**kinds.get('seat',{}),'fill':'#253759FF','stroke':'#253759FF','strokeWidth':0}
 for n in d['nodes']:
  if n.get('kind')=='group':continue
  s=n.setdefault('style',{})
  if 'stroke' in s:s.update(stroke='#253759FF',strokeWidth=3)
  s['label']={**s.get('label',{}),**label}
 return d

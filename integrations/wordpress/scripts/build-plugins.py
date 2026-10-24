"""Generate two self-contained plugins from one source; no runtime core dependency."""
from pathlib import Path
import argparse,hashlib,json,re,struct
ROOT=Path(__file__).resolve().parents[1]
SHARED=ROOT/'shared'
PRODUCTS=json.loads((ROOT/'products.json').read_text())
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--product',choices=[p['slug'] for p in PRODUCTS])
selected=parser.parse_args().product
PRODUCTS=[p for p in PRODUCTS if selected is None or p['slug']==selected]
CS=json.loads((SHARED/'cs_CZ.json').read_text())
FILES={'plugin.php.in':'{slug}.php','embed.php.in':'includes/embed.php','admin.php.in':'includes/admin.php','editor.js.in':'blocks/ticket-form/editor.js','style.css.in':'blocks/ticket-form/style.css','block.json.in':'blocks/ticket-form/block.json','readme.txt.in':'readme.txt'}

def replace(source,p):
 values={k.upper():str(v) for k,v in p.items()}
 for key,value in values.items():source=source.replace('@@'+key+'@@',value)
 if re.search(r'@@[A-Z_]+@@',source):raise ValueError('Unresolved product token')
 return source

def mo(messages):
 keys=sorted(messages);ids=b'';strings=b'';index=[];values=[]
 for key in keys:
  a=key.encode();b=messages[key].encode();index.append((len(a),len(ids)));values.append((len(b),len(strings)));ids+=a+b'\0';strings+=b+b'\0'
 n=len(keys);idstart=28+16*n;valuestart=idstart+len(ids)
 return struct.pack('<7I',0x950412de,0,n,28,28+8*n,0,0)+b''.join(struct.pack('<2I',size,idstart+offset) for size,offset in index)+b''.join(struct.pack('<2I',size,valuestart+offset) for size,offset in values)+ids+strings

manifest={}
for p in PRODUCTS:
 slug=p['slug'];assert re.fullmatch(r'[a-z][a-z0-9-]+',slug)
 assert re.fullmatch(r'[A-Za-z]+',p['namespace']) and re.fullmatch(r'\d+\.\d+\.\d+',p['version'])
 assert re.fullmatch(r'https://[a-z0-9.-]+',p['origin'])
 out=ROOT/slug;assert not out.is_symlink();out.mkdir(exist_ok=True)
 generated={}
 for source,target in FILES.items():generated[target.format(slug=slug)]=replace((SHARED/source).read_text(),p)
 # All textdomain arguments and namespaces are literal in the distributed sources.
 messages=set()
 for name,text in generated.items():
  if name.endswith(('.php','.js')):
   for match in re.finditer(r"(?:__|esc_html__|esc_html_e)\(\s*'((?:\\.|[^'\\])*)'\s*,\s*'"+re.escape(slug)+"'",text):messages.add(match[1].replace("\\'","'").replace('\\\\','\\'))
 block=json.loads(generated['blocks/ticket-form/block.json']);messages.update([p['name'],block['description']])
 description=re.search(r' \* Description: (.+)',generated[slug+'.php'])[1];messages.add(description)
 translated={replace(k,p):replace(v,p) for k,v in CS.items()}
 header=f"Project-Id-Version: {p['name']} {p['version']}\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\nLanguage: cs_CZ\nPlural-Forms: nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;\nX-Domain: {slug}\n"
 quote=lambda value:json.dumps(value,ensure_ascii=False)
 po='msgid ""\nmsgstr '+quote(header)+'\n\n'
 pot='# Copyright (C) 2026 Festapp\n# License: GPL-2.0-or-later\nmsgid ""\nmsgstr '+quote(header.replace('Language: cs_CZ','Language: '))+'\n\n'
 catalog={'':header}
 jed={'':{'domain':'messages','lang':'cs_CZ','plural-forms':'nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;'}}
 for message in sorted(messages):
  value=translated.get(message,'');po+='msgid '+quote(message)+'\nmsgstr '+quote(value)+'\n\n';pot+='msgid '+quote(message)+'\nmsgstr ""\n\n'
  if value:catalog[message]=value;jed[message]=[value]
 # Block metadata uses gettext contexts; context belongs in the key, never
 # in the visible translated value (also used by the plugin list).
 for context,message in [('block title',p['name']),('block description',block['description'])]:
  value=translated.get(message,'')
  entry='msgctxt '+quote(context)+'\nmsgid '+quote(message)+'\n'
  po+=entry+'msgstr '+quote(value)+'\n\n';pot+=entry+'msgstr ""\n\n'
  if value:catalog[context+'\x04'+message]=value;jed[context+'\x04'+message]=[value]
 generated[f'languages/{slug}-cs_CZ.po']=po;generated[f'languages/{slug}.pot']=pot
 generated[f'languages/{slug}-cs_CZ.mo']=mo(catalog)
 script_hash=hashlib.md5(b'blocks/ticket-form/editor.js').hexdigest()
 generated[f'languages/{slug}-cs_CZ-{script_hash}.json']=json.dumps({'domain':'messages','locale_data':{'messages':jed}},ensure_ascii=False,separators=(',',':'))+'\n'
 generated['LICENSE.txt']=(SHARED/'LICENSE.txt').read_bytes()
 for old in out.rglob('*'):
  if old.is_file() and old.relative_to(out).as_posix() not in generated:old.unlink()
 for name,value in generated.items():
  target=out/name;assert not target.is_symlink();target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(value if isinstance(value,bytes) else value.encode())
 manifest[slug]={'files':{name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in sorted(generated)},'messages':len(messages),'czech_translations':len(catalog)-1}
manifest['shared_inputs']={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'products.json',ROOT/'scripts/build-plugins.py',ROOT/'scripts/package.py',*sorted(SHARED.iterdir())] if p.is_file()}
(ROOT/'evidence/shared-build.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Generated {len(PRODUCTS)} selected plugin(s) from shared sources, with readable code and Czech translations')

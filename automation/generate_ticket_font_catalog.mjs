import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
export function extractFaceVariants(source, method) {
  const start=source.indexOf(`static TextStyle ${method}({`);
  if(start<0)throw Error(`Missing method ${method}`);
  const end=source.indexOf('return googleFontsTextStyle(',start);
  if(end<0)throw Error('Unknown google_fonts format');
  const variants=[...source.slice(start,end).matchAll(/fontWeight: FontWeight.w(\d+),\s*fontStyle: FontStyle.(normal|italic),?\s*\):\s*GoogleFontsFile\(\s*'([a-f0-9]{64})',\s*(\d+),?\s*\)/g)].map(m=>({weight:+m[1],style:m[2],sha256:m[3],byteLength:+m[4]}));
  if(!variants.length)throw Error(`Unknown variants ${method}`);
  return variants;
}
export function extractVariants(source, method) {
  const variants=extractFaceVariants(source,method);
  return variants.filter(v=>v.style==='normal').sort((a,b)=>Math.abs(a.weight-400)-Math.abs(b.weight-400)||a.weight-b.weight)[0]??null;
}
export function generate(root) {
  const configPath=resolve(root,'.dart_tool/package_config.json');
  const pkg=JSON.parse(readFileSync(configPath)).packages.find(p=>p.name==='google_fonts');
  const pkgRoot=fileURLToPath(new URL(pkg.rootUri.endsWith('/')?pkg.rootUri:pkg.rootUri+'/',pathToFileURL(configPath)));
  const version=readFileSync(resolve(pkgRoot,'pubspec.yaml'),'utf8').match(/^version: (.+)$/m)[1];
  const lock=readFileSync(resolve(root,'pubspec.lock'),'utf8');
  const lockedVersion=lock.match(/^  google_fonts:\n((?: {4}.*\n)+)/m)?.[1].match(/    version: "([^"]+)"/)?.[1];
  if(lockedVersion!==version)throw Error('Package/lock drift');
  const all=readFileSync(resolve(pkgRoot,'lib/src/google_fonts_all_parts.dart'),'utf8');
  const names=[...all.slice(all.indexOf('asMap() => const {'),all.indexOf('static Map<String, TextTheme')).matchAll(/'([^']+)': Part([A-Z]).(\w+),/g)];
  if(names.length<1000)throw Error('Unknown family map');
  const parts=new Map();let fonts=[];const defaultFonts=[];const familyFaces=new Map();const unsupportedFamilies=[];
  for(const [,family,part,method] of names){
    if(!parts.has(part))parts.set(part,readFileSync(resolve(pkgRoot,`lib/src/google_fonts_parts/part_${part.toLowerCase()}.dart`),'utf8'));
    const v=extractVariants(parts.get(part),method);
    if(!v)unsupportedFamilies.push(family);
    const record=v=>({id:`gf:${v.sha256}`,family,...v,source:'google',packageVersion:version,extension:'ttf'});
    if(v)defaultFonts.push(record(v));
    const faces=extractFaceVariants(parts.get(part),method).filter(f=>f.weight===400||f.weight===700);
    familyFaces.set(family,Object.fromEntries(faces.map(f=>[`${f.weight}:${f.style}`,`gf:${f.sha256}`])));
    fonts.push(...faces.map(record));
  }
  for(const [family,file,kind,weight] of [['Futura PT','font.ttf','futura-pt-book',400],['Roboto Slab (legacy)','roboto-slab.ttf','roboto-slab-static',400],['Roboto (legacy)','roboto.ttf','roboto-unpacked',400],['Russo One (legacy)','russo-one.ttf','russo-one-unpacked',400]]){
    const bytes=readFileSync(resolve(root,'supabase/functions/_shared/ticket-assets',file));const sha256=createHash('sha256').update(bytes).digest('hex');
    const asset={id:`builtin:${kind}:${sha256}`,family,weight,style:'normal',sha256,byteLength:bytes.length,source:'bundled',file,extension:file.split('.').pop(),packageVersion:'historical-2026-10-03'};
    defaultFonts.push(asset);familyFaces.set(family,{[`${weight}:normal`]:asset.id});
  }
  const familyOrder=(a,b)=>a.family<b.family?-1:a.family>b.family?1:0;
  defaultFonts.sort(familyOrder);
  // Preserve every historical face and its original metadata, then append new
  // exact faces. Shared font bytes may be referenced by several family names.
  const byId=new Map();for(const face of defaultFonts)if(!byId.has(face.id))byId.set(face.id,face);
  for(const face of fonts.sort(familyOrder))if(!byId.has(face.id))byId.set(face.id,face);
  fonts=[...byId.values()].sort((a,b)=>familyOrder(a,b)||a.weight-b.weight||(a.style<b.style?-1:a.style>b.style?1:0));
  const families=[...familyFaces.entries()].map(([family,faces])=>{
    const payload={faces:Object.fromEntries(Object.entries(faces).sort(([a],[b])=>a<b?-1:a>b?1:0)),family,version:1};
    const hash=createHash('sha256').update(JSON.stringify(payload)).digest('hex');
    return {id:`font-family:${hash}`,hash,...payload};
  }).sort(familyOrder);
  const defaultFaceIds=defaultFonts.map(f=>f.id);
  const json=JSON.stringify({version:2,googleFontsVersion:version,unsupportedFamilies,defaultFaceIds,fonts,families})+'\n';
  const seed='-- Generated. Append-only: never delete historical IDs.\nINSERT INTO public.ticket_font_assets(id,metadata) VALUES\n'+fonts.map(f=>`('${f.id}','${JSON.stringify(f).replaceAll("'","''")}'::jsonb)`).join(',\n')+'\nON CONFLICT(id) DO NOTHING;\n';
  const legacyFiles={futura:'font.ttf',robotoSlab:'roboto-slab.ttf',roboto:'roboto.ttf',russoOne:'russo-one.ttf'};
  const dart='// Generated from the immutable font catalog.\nconst legacyTicketFontIds = <String, String>{\n'+Object.entries(legacyFiles).map(([key,file])=>`  '${key}':\n      '${fonts.find(f=>f.file===file).id}',`).join('\n')+'\n};\n';
  const familySeed='-- Generated immutable manifests from the same Ticket font catalog.\nINSERT INTO public.ticket_font_families(id,manifest) VALUES\n'+families.map(f=>`('${f.id}','${JSON.stringify(f).replaceAll("'","''")}'::jsonb)`).join(',\n')+'\nON CONFLICT(id) DO NOTHING;\n';
  return new Map([['database/seeds/ticket_font_families.sql',familySeed],['lib/components/fonts/ticket_font_ids.dart',dart],['supabase/functions/_shared/ticket-assets/font-catalog.json',json],['database/seeds/ticket_font_assets.sql',seed]]);
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
  for(const [path,content] of generate(root)){
    if(process.argv.includes('--check')){if(readFileSync(resolve(root,path),'utf8')!==content)throw Error(`Catalog drift: ${path}`);}else writeFileSync(resolve(root,path),content);
  }
  console.log('Ticket font catalog OK');
}

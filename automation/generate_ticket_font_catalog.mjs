import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
export function extractVariants(source, method) {
  const start=source.indexOf(`static TextStyle ${method}({`);
  if(start<0)throw Error(`Missing method ${method}`);
  const end=source.indexOf('return googleFontsTextStyle(',start);
  if(end<0)throw Error('Unknown google_fonts format');
  const variants=[...source.slice(start,end).matchAll(/fontWeight: FontWeight.w(\d+),\s*fontStyle: FontStyle.(normal|italic),?\s*\):\s*GoogleFontsFile\(\s*'([a-f0-9]{64})',\s*(\d+),?\s*\)/g)].map(m=>({weight:+m[1],style:m[2],sha256:m[3],byteLength:+m[4]}));
  if(!variants.length)throw Error(`Unknown variants ${method}`);
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
  const parts=new Map();const fonts=[];const unsupportedFamilies=[];
  for(const [,family,part,method] of names){
    if(!parts.has(part))parts.set(part,readFileSync(resolve(pkgRoot,`lib/src/google_fonts_parts/part_${part.toLowerCase()}.dart`),'utf8'));
    const v=extractVariants(parts.get(part),method);
    if(!v)unsupportedFamilies.push(family);
    if(v)fonts.push({id:`gf:${v.sha256}`,family,...v,source:'google',packageVersion:version,extension:'ttf'});
  }
  for(const [family,file,kind,weight] of [['Futura PT','font.ttf','futura-pt-book',400],['Roboto Slab (legacy)','roboto-slab.ttf','roboto-slab-static',400],['Roboto (legacy)','roboto.ttf','roboto-unpacked',400],['Russo One (legacy)','russo-one.ttf','russo-one-unpacked',400]]){
    const bytes=readFileSync(resolve(root,'supabase/functions/_shared/ticket-assets',file));const sha256=createHash('sha256').update(bytes).digest('hex');
    fonts.push({id:`builtin:${kind}:${sha256}`,family,weight,style:'normal',sha256,byteLength:bytes.length,source:'bundled',file,extension:file.split('.').pop(),packageVersion:'historical-2026-10-03'});
  }
  fonts.sort((a,b)=>a.family<b.family?-1:a.family>b.family?1:0);
  const json=JSON.stringify({version:1,googleFontsVersion:version,unsupportedFamilies,fonts},null,2)+'\n';
  const seed='-- Generated. Append-only: never delete historical IDs.\nINSERT INTO public.ticket_font_assets(id,metadata) VALUES\n'+fonts.map(f=>`('${f.id}','${JSON.stringify(f).replaceAll("'","''")}'::jsonb)`).join(',\n')+'\nON CONFLICT(id) DO NOTHING;\n';
  const legacyFiles={futura:'font.ttf',robotoSlab:'roboto-slab.ttf',roboto:'roboto.ttf',russoOne:'russo-one.ttf'};
  const dart='// Generated from the immutable font catalog.\nconst legacyTicketFontIds = <String, String>{\n'+Object.entries(legacyFiles).map(([key,file])=>`  '${key}':\n      '${fonts.find(f=>f.file===file).id}',`).join('\n')+'\n};\n';
  return new Map([['lib/components/fonts/ticket_font_ids.dart',dart],['supabase/functions/_shared/ticket-assets/font-catalog.json',json],['assets/fonts/ticket-font-catalog.json',json],['database/seeds/ticket_font_assets.sql',seed]]);
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
  const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
  for(const [path,content] of generate(root)){
    if(process.argv.includes('--check')){if(readFileSync(resolve(root,path),'utf8')!==content)throw Error(`Catalog drift: ${path}`);}else writeFileSync(resolve(root,path),content);
  }
  console.log('Ticket font catalog OK');
}

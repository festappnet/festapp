import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {readFileSync,readdirSync} from 'node:fs';
import {generate,extractVariants,extractFaceVariants} from '../generate_ticket_font_catalog.mjs';
test('deterministic catalog maps display families, locks version and matches all outputs',()=>{
  const outputs=generate(process.cwd());for(const [file,content] of outputs)assert.equal(readFileSync(file,'utf8'),content);
  const fonts=JSON.parse(outputs.get('supabase/functions/_shared/ticket-assets/font-catalog.json')).fonts;
  for(const name of ['Roboto Slab','Russo One','Roboto','Futura PT'])assert.ok(fonts.find(f=>f.family===name));
  assert.ok(fonts.every(f=>f.id.endsWith(f.sha256)));
});
test('selects nearest normal weight, lower tie; malformed package fails closed',()=>{
 const variant=(weight,style='normal')=>`const GoogleFontsVariant(fontWeight: FontWeight.w${weight}, fontStyle: FontStyle.${style}): GoogleFontsFile('${'a'.repeat(64)}', 10),`;
 const source=`static TextStyle sample({}) { ${variant(500)} ${variant(300)} ${variant(400,'italic')} return googleFontsTextStyle(`;
 assert.equal(extractVariants(source,'sample').weight,300);
 assert.equal(extractVariants(`static TextStyle sample({}) {${variant(400,'italic')} return googleFontsTextStyle(`,'sample'),null);
 assert.throws(()=>extractVariants('unrecognized','sample'));
});

test('face extraction retains every actual regular, bold, italic and bold-italic variant',()=>{
 const variants=[[400,'normal'],[700,'normal'],[400,'italic'],[700,'italic']];
 const source='static TextStyle sample({}) {'+variants.map(([weight,style],i)=>`const GoogleFontsVariant(fontWeight: FontWeight.w${weight}, fontStyle: FontStyle.${style}): GoogleFontsFile('${String(i).repeat(64)}', ${10+i}),`).join('')+' return googleFontsTextStyle(';
 const faces=extractFaceVariants(source,'sample');
 assert.deepEqual(faces.map(({weight,style})=>[weight,style]),variants);
 assert.equal(new Set(faces.map(f=>f.sha256)).size,4);
 assert.equal(extractVariants(source,'sample').sha256,faces[0].sha256);
});

test('staged function bundle proof includes catalog and all three bundled defaults',async()=>{
 const {execFileSync}=await import('node:child_process');
 const proof=JSON.parse(execFileSync('python3',['automation/hetzner-supabase/runtime/ticket-font-asset-proof.py','supabase/functions/_shared/ticket-assets'],{encoding:'utf8'}));
 const manifest=JSON.parse(readFileSync('supabase/functions/_shared/ticket-assets/preview-manifest.json','utf8'));
 assert.deepEqual(Object.keys(proof).sort(),['font-catalog.json','preview-manifest.json',...Object.values(manifest.fonts).map(a=>a.file),...Object.values(manifest.artwork).map(a=>a.file)].sort());
 for(const item of Object.values(proof))assert.ok(item.bytes>0&&item.sha256.length===64);
 const builder=readFileSync('automation/hetzner-supabase/runtime/build-production-function-bundle.sh','utf8');
 assert.match(builder,/ticket-font-asset-proof.py/);assert.match(builder,/ticket_font_assets:\$ticket_font_assets/);
});

test('family manifests use exact face identities and unavailable variants remain absent',async()=>{
 const {createHash}=await import('node:crypto');
 const value=JSON.parse(generate(process.cwd()).get('supabase/functions/_shared/ticket-assets/font-catalog.json'));
 const assets=new Map(value.fonts.map(f=>[f.id,f]));
 for(const manifest of value.families){
  const {faces,family,version}=manifest;
  assert.equal(manifest.hash,createHash('sha256').update(JSON.stringify({faces,family,version})).digest('hex'));
  assert.equal(manifest.id,`font-family:${manifest.hash}`);
  for(const [key,id] of Object.entries(faces)){
   const [weight,style]=key.split(':');assert.ok([400,700].includes(+weight));
   assert.equal(assets.get(id).weight,+weight);assert.equal(assets.get(id).style,style);
  }
 }
 assert.equal(Object.keys(value.families.find(f=>f.family==='Roboto').faces).length,4);
 assert.equal(value.families.find(f=>f.family==='Tiro Devanagari Hindi').faces['700:normal'],undefined);
 assert.ok(value.defaultFaceIds.every(id=>assets.has(id)));
});

test('ordered forward migrations contain canonical registry, seeds and current validators without changing history',()=>{
 const migrations=readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort().map(f=>readFileSync(`supabase/migrations/${f}`,'utf8')).join('\n');
 for(const source of ['database/tables/ticket_font_assets.sql','database/seeds/ticket_font_assets.sql','database/tables/ticket_font_families.sql','database/seeds/ticket_font_families.sql','database/policies/05_ticket_font_storage.sql'])assert.ok(migrations.includes(readFileSync(source,'utf8')),source);
 const definitions=readFileSync('database/functions/others/ticket_layout.sql','utf8').match(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;/g)??[];
 assert.ok(definitions.length);for(const definition of definitions)assert.ok(migrations.includes(definition),definition.slice(0,100));
 assert.match(migrations,/ON CONFLICT\(id\) DO NOTHING/);
});

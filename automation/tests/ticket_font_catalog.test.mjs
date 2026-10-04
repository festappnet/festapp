import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {generate,extractVariants} from '../generate_ticket_font_catalog.mjs';
test('deterministic catalog maps display families, locks version and matches all outputs',()=>{
  const outputs=generate(process.cwd());for(const [file,content] of outputs)assert.equal(readFileSync(file,'utf8'),content);
  const fonts=JSON.parse(outputs.get('assets/fonts/ticket-font-catalog.json')).fonts;
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

test('staged function bundle proof includes catalog and all three bundled defaults',async()=>{
 const {execFileSync}=await import('node:child_process');
 const proof=JSON.parse(execFileSync('python3',['automation/hetzner-supabase/runtime/ticket-font-asset-proof.py','supabase/functions/_shared/ticket-assets'],{encoding:'utf8'}));
 assert.deepEqual(Object.keys(proof).sort(),['font-catalog.json','font.ttf','roboto-slab.ttf','roboto.ttf','russo-one.ttf']);
 for(const item of Object.values(proof))assert.ok(item.bytes>0&&item.sha256.length===64);
 const builder=readFileSync('automation/hetzner-supabase/runtime/build-production-function-bundle.sh','utf8');
 assert.match(builder,/ticket-font-asset-proof.py/);assert.match(builder,/ticket_font_assets:\$ticket_font_assets/);
});

test('migration contains the canonical registry seed and validator without losing older identities',()=>{
 const migration=readFileSync('supabase/migrations/20261003130000_ticket_fonts.sql','utf8');
 for(const source of ['database/tables/ticket_font_assets.sql','database/seeds/ticket_font_assets.sql','database/policies/05_ticket_font_storage.sql'])assert.ok(migration.includes(readFileSync(source,'utf8')));
 // Compare evolving function definitions with the complete ordered layout upgrade, not one older snapshot.
 const layoutMigrations = migration + readFileSync('supabase/migrations/20261003150000_ticket_font_upgrade_save.sql','utf8') + readFileSync('supabase/migrations/20261003180000_ticket_canvas_opacity.sql','utf8');
 const definitions = readFileSync('database/functions/others/ticket_layout.sql','utf8').match(/CREATE OR REPLACE FUNCTION[\s\S]*?\$\$;/g) ?? [];
 assert.ok(definitions.length);
 for (const definition of definitions) assert.ok(layoutMigrations.includes(definition));
 assert.match(migration,/ON CONFLICT\(id\) DO NOTHING/);
});

// Regenerate synthetic SQL readbacks, always rollback, never load .env credentials.
import pg from '../web_client/node_modules/pg/lib/index.js';
import {readFileSync,writeFileSync} from 'node:fs';
const root=new URL('../',import.meta.url);
const client=new pg.Client({connectionString:'postgresql://postgres:postgres@127.0.0.1:59522/postgres'});
await client.connect();
try {
 const marker=await client.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
 if(marker.rows[0]?.project!=='festapp-blueprint-b-e2e-20261019')throw Error('Disposable marker mismatch');
 await client.query('BEGIN');
 await client.query(readFileSync(new URL('database/tests/helpers/assertions.sql',root),'utf8'));
 await client.query(readFileSync(new URL('database/tests/blueprint/layout_integration_test.sql',root),'utf8'));
 for(const [setting,file] of [['blueprint_font_roundtrip','scoped-font-sql-roundtrip.json'],['blueprint_numeric_roundtrip','numeric-sql-roundtrip.json']]){
  const result=await client.query('SELECT current_setting($1)::jsonb AS corpus',[`festapp_test_support.${setting}`]);
  writeFileSync(new URL(`test/fixtures/blueprint/${file}`,root),JSON.stringify(result.rows[0].corpus,null,2)+'\n');
 }
 console.log('SQL font and numeric corpus regenerated: admin/public/setup/copy, transaction rolled back.');
} finally {await client.query('ROLLBACK');await client.end();}

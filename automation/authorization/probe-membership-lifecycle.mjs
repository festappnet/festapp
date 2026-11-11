// Read-only report of behavior in a marker-verified disposable database.
// All synthetic fixture writes are rolled back; no production target is accepted.
import {openDisposableDatabase} from '../../tools/festapp/test/postgres.mjs';
import {fixture} from './benchmark.mjs';
const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
await db.query('BEGIN');
try {
 const f=await fixture(db,1);
 await db.query('update occasion_users set is_editor=false,is_manager=false,is_editor_view=false,is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
 await db.query('update unit_users set is_editor=false,is_manager=false,is_editor_view=true where unit=$1 and "user"=$2',[f.unit,f.actor]);
 const observe=async stage=>{
  await db.query('SET LOCAL ROLE authenticated');
  const context=(await db.query('select get_app_config_v218($1) value',[{organization:f.org,link:f.link,platform:{platform:'web'}}])).rows[0].value;
  const predicates=(await db.query('select can_author_forms($1) as forms,can_write_news($1) as news,can_write_orders($1) as orders,can_manage_occasion_participants($1) as participants',[f.occasion])).rows[0];
  await db.query('RESET ROLE');
  const membership=(await db.query('select is_editor,is_manager,is_editor_view,is_editor_order,is_editor_order_view from occasion_users where occasion=$1 and "user"=$2',[f.occasion,f.actor])).rows[0];
  console.log(JSON.stringify({stage,contextCode:context.code,capabilities:Object.fromEntries(['forms.write','news.write','orders.write','participants.write','occasions.create'].map(k=>[k,context.capabilities?.[k]])),predicates,membership}));
 };
 await observe('existing membership before promotion');
 await db.query('update unit_users set is_editor=true where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await observe('existing membership after unit editor promotion');
 await db.query('update unit_users set is_editor=false,is_manager=true where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await observe('existing membership after unit manager promotion');
 await db.query('update unit_users set is_editor=true,is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await db.query('delete from occasion_users where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
 await observe('first event visit as unit editor');
 await db.query('update unit_users set is_editor=false,is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await observe('unit role removed after first event visit');
} finally {await db.query('ROLLBACK');await db.end();}

// Import configuration snapshots into the dedicated local Wizard workspace.
// No source database connection, customers, orders, payments or live secrets.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import pg from 'pg';

const snapshotPath = process.argv[2];
if (!snapshotPath) throw new Error('Usage: node web_client/scripts/import_occasion_setup_sources.js <private-snapshot.json>');
const backend = path.resolve(process.env.FESTAPP_WIZARD_WORKSPACE || path.join('..', 'festapp-wizard-local'));
if (!fs.existsSync(path.join(backend, 'bootstrap-complete'))) throw new Error('Owned local workspace has not been bootstrapped');
const containers = execFileSync('docker', ['ps', '--format', '{{.Names}} {{.Ports}}'], { encoding: 'utf8' });
if (!containers.split('\n').some(line => line.startsWith(`supabase_db_${path.basename(backend)} `) && line.includes(':56822->5432/'))) {
  throw new Error('Expected local container does not own port 56822');
}
const snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
if (typeof snapshot.tenant !== 'string' || !Array.isArray(snapshot.sources)) throw new Error('Invalid source snapshot');
const client = new pg.Client({ connectionString: 'postgresql://postgres:postgres@127.0.0.1:56822/postgres' });
await client.connect();
let imported = 0;
try {
  await client.query('BEGIN');
  const local = await client.query('SELECT id,organization FROM public.units ORDER BY id LIMIT 1');
  if (!local.rows.length) throw new Error('No seeded local unit');
  const { id: unit, organization } = local.rows[0];
  // Identifiers below are fixed by code; every source value is parameterized.
  async function insert(table, columns, values) {
    const result = await client.query(`INSERT INTO ${table}(${columns.map(c => `"${c}"`).join(',')}) VALUES(${values.map((_, i) => `$${i + 1}`).join(',')}) RETURNING id`,
      values.map(v => v !== null && typeof v === 'object' ? JSON.stringify(v) : v ?? null));
    return result.rows[0].id;
  }
  for (const source of snapshot.sources) {
    const o = source.occasion;
    const sourceKey = String(o.id);
    const sourceKind = `wizard-local-${snapshot.tenant}`;
    const existing = await client.query("SELECT id FROM public.occasions WHERE external_source=$1 AND external_id=$2", [sourceKind,sourceKey]);
    if (existing.rows.length) {
      if (process.argv.includes('--refresh-media')) {
        const localPlans = await client.query('SELECT id,objects FROM eshop.blueprints WHERE occasion=$1 ORDER BY id', [existing.rows[0].id]);
        if (localPlans.rows.length !== (source.blueprints ?? []).length) throw new Error('Snapshot plan count differs; refusing to update');
        for (let index = 0; index < localPlans.rows.length; index++) {
          const localPlan = localPlans.rows[index];
          const sourcePlan = source.blueprints[index];
          const labels = new Map(sourcePlan.objects.map(o => [`${o.x}:${o.y}:${o.type}`, o.title]));
          const objects = localPlan.objects.map(o => ({ ...o, title: labels.get(`${o.x}:${o.y}:${o.type}`) ?? o.title }));
          await client.query('UPDATE eshop.blueprints SET objects=$1,background_svg=$2 WHERE id=$3', [JSON.stringify(objects),sourcePlan.background_svg,localPlan.id]);
          for (const object of objects.filter(o => o.type === 'spot')) {
            await client.query('UPDATE eshop.spots SET title=$1 WHERE id=$2 AND blueprint=$3', [object.title,object.id,localPlan.id]);
          }
        }
      }
      continue;
    }
    const occasion = await insert('public.occasions',
      ['unit','organization','title','link','start_time','end_time','description','data','features','is_open','is_hidden','external_source','external_id'],
      [unit,organization,o.title,o.link,o.start_time,o.end_time,o.description,o.data ?? {},o.features ?? [],false,true,sourceKind,sourceKey]);
    const types = new Map();
    const products = new Map();
    const plans = new Map();
    for (const form of source.forms ?? []) {
      for (const field of form.fields ?? []) {
        const type = field.product_type_data;
        if (!type || types.has(String(type.id))) continue;
        const typeId = await insert('eshop.product_types', ['occasion','title','description','type','data'],
          [occasion,type.title,type.description,type.type,type.data ?? {}]);
        types.set(String(type.id), typeId);
        for (const product of type.products ?? []) {
          const id = await insert('eshop.products', ['occasion','product_type','title','description','price','currency_code','maximum','is_hidden','order','data'],
            [occasion,typeId,product.title,product.description,product.price,product.currency_code,product.maximum,product.is_hidden ?? false,product.order,product.data ?? {}]);
          products.set(String(product.id), id);
        }
      }
    }
    for (const plan of source.blueprints ?? []) {
      const id = await insert('eshop.blueprints', ['occasion','organization','title','configuration','objects','groups','background_svg'],
        [occasion,organization,plan.title,plan.configuration,[],plan.groups ?? [],plan.background_svg]);
      plans.set(String(plan.id), id);
      const objects = [];
      for (const original of plan.objects ?? []) {
        const object = { ...original, state: 'available' };
        delete object.id;
        delete object.secret;
        delete object.order_product_ticket;
        const product = products.get(String(original.product)) ?? null;
        if (object.type === 'spot') {
          object.id = Number(await insert('eshop.spots', ['occasion','blueprint','title','product','state'],
            [occasion,id,object.title,product,'available']));
        }
        object.product = product === null ? null : Number(product);
        objects.push(object);
      }
      await client.query('UPDATE eshop.blueprints SET objects=$1 WHERE id=$2', [JSON.stringify(objects),id]);
    }
    for (const form of source.forms ?? []) {
      const id = await insert('public.forms', ['occasion','title','link','type','data','header','header_off','deadline_duration_seconds','blueprint','is_open'],
        [occasion,form.title,form.link,form.type,form.data ?? {},form.header,form.header_off,form.deadline_duration_seconds,plans.get(String(form.blueprint)),false]);
      for (const field of form.fields ?? []) {
        await insert('public.form_fields', ['form','title','description','type','data','is_required','is_hidden','is_ticket_field','order','product_type'],
          [id,field.title,field.description,field.type,field.data ?? {},field.is_required ?? false,field.is_hidden ?? false,field.is_ticket_field ?? false,field.order,types.get(String(field.product_type_data?.id))]);
      }
    }
    for (const event of source.program ?? []) {
      await insert('public.events', ['occasion','title','start_time','end_time','description'],
        [occasion,event.title,event.start_time,event.end_time,event.description]);
    }
    for (const info of source.information ?? []) {
      await insert('public.information', ['occasion','title','description','type','data'],
        [occasion,info.title,info.description,info.type,info.data ?? {}]);
    }
    imported++;
  }
  await client.query('COMMIT');
  console.log(`Imported ${imported} source configurations into the local Wizard.`);
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  await client.end();
}

// Read-only unless --apply is explicit. Select exactly one organization and
// supply the authorized author's UUID. Never prints stored HTML or contacts.
import pg from 'pg';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {convertLegacyPresale} from './presale_content_converter.mjs';
const args = process.argv.slice(2);
const option = name => args[args.indexOf(name)+1];
if (!args.includes('--organization') || !args.includes('--actor') || !args.includes('--locale') || !process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL and --organization ID --actor UUID --locale cs|en|sk|de|pl|uk required; --apply is a separate authorized operation');
}
const organization = Number(option('--organization')); const actor = option('--actor');
const locale = option('--locale');
if (!['cs','en','sk','de','pl','uk'].includes(locale)) throw new Error('Explicit supported tenant locale required');
if (!Number.isSafeInteger(organization) || organization <= 0 || !/^[0-9a-f-]{36}$/iu.test(actor)) throw new Error('Invalid scope');
const client = new pg.Client({connectionString:process.env.DATABASE_URL});
await client.connect();
try {
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
    await client.query("select set_config('request.jwt.claim.sub',$1,true)",[actor]);
    const counts = (await client.query(`select count(*)::int total,
      count(*) filter(where not coalesce(public.can_author_forms(f.occasion),false))::int unauthorized
      from public.forms f join public.occasions o on o.id=f.occasion where o.organization=$1`,[organization])).rows[0];
    if (counts.unauthorized) throw new Error('Author does not cover the full selected organization');
    const {rows} = await client.query(`select f.id,public.normalize_form_metadata_internal(f.data) data,coalesce(v.version,0) version,
      encode(extensions.digest(convert_to(coalesce(f.data,'{}')::text,'UTF8'),'sha256'),'hex') hash,
      public.get_form_authoring_snapshot_internal(f.id) snapshot
      from public.forms f join public.occasions o on o.id=f.occasion
      left join public.client_aggregate_versions v on v.aggregate_type='form' and v.scope_type='occasion' and v.scope_id=f.occasion and v.aggregate_id=f.id::text
      where o.organization=$1 and public.can_author_forms(f.occasion) and f.data#>>'{design,presale_header}' is null order by f.id`,[organization]);
    const title = JSON.parse(readFileSync(new URL(`../../assets/translations/${locale}.json`,import.meta.url))).FeatureFormSettings?.registrationStart;
    const results = [];
    for (const row of rows) {
        const converted = convertLegacyPresale(row.data,{registrationStart:title});
        const snapshot = {...row.snapshot,form:{...row.snapshot.form,data:converted.metadata}};
        const budget = (await client.query('select public.presale_conversion_budgets_internal($1,$2,$3) budget',
            [converted.metadata,converted.html,snapshot])).rows[0].budget;
        results.push({row,converted,budget});
    }
    console.log(JSON.stringify({organization,totalForms:counts.total,pendingForms:rows.length,blocked:results.filter(r=>r.budget.blocked).map(r=>({id:r.row.id,...r.budget})),
      maxima: Object.fromEntries(['characters','settingsBytes','transportBytes','snapshotBytes'].map(k=>[k,Math.max(0,...results.map(r=>r.budget[k]))]))}));
    if (results.some(r=>r.budget.blocked)) throw new Error('PRESALE_SIZE_BLOCKED: no forms converted');
    if (args.includes('--apply')) for (const {row,converted} of results) {
        await client.query('select public.convert_form_presale_content($1,$2,$3,$4,$5)',[row.id,row.version,row.hash,converted.html,randomUUID()]);
    }
    await client.query(args.includes('--apply')?'COMMIT':'ROLLBACK');
} catch (error) { await client.query('ROLLBACK'); throw error; }
finally { await client.end(); }

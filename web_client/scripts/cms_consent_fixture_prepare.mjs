// Canonical SQL configuration/export, scoped strictly to the owned local fixture.
import fs from 'node:fs';
import path from 'node:path';
import pg from 'pg';
const fixture=path.resolve(process.argv[2]),base=Number(process.argv[3]),offset=Number(process.argv[4]);
const platform=process.argv[5];const marker=path.basename(fixture);
if(!/^festapp-cms-consent-[a-z0-9-]+$/.test(marker) || !Number.isInteger(base) || base<1024 || base>65480 || ![31,34,35,36,37,38].includes(offset) || !['wordpress','joomla','wix','html'].includes(platform))throw Error('Owned fixture parameters required');
const client=new pg.Client({connectionString:`postgresql://postgres:postgres@127.0.0.1:${base+22}/postgres`});await client.connect();
try {
 if((await client.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0]?.project!==marker)throw Error('Foreign database refused');
 const origin=n=>`https://127.0.0.1:${base+n}`;
 const sites=[31,34,35,36,37,38].map(origin);const service=origin(32),site=origin(offset);
 const actor=(await client.query("SELECT id FROM auth.users WHERE email='1+t@t.com'")).rows[0]?.id;
 if(!actor)throw Error('Canonical synthetic manager required');
 if((await client.query('SELECT title FROM public.organizations WHERE id=1')).rows[0]?.title!=='Test Organization')throw Error('Canonical synthetic organization required');
 await client.query('BEGIN');
 await client.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
 await client.query(`UPDATE public.organizations SET data=coalesce(data,'{}')||$1::jsonb WHERE id=1`,[JSON.stringify({DEFAULT_URL:service,FORM_MEASUREMENT_ENABLED:true,DEFAULT_LANGUAGE:'cs',DEFAULT_UNIT:1,APP_NAME:'Festapp'})]);
 await client.query(`UPDATE public.units SET data=coalesce(data,'{}')||$1::jsonb WHERE id=1`,[JSON.stringify({measurement_enabled:true,measurement_consent_bridge:true,measurement_websites:sites,measurement_gtm_container:'GTM-AB12',measurement_privacy_url:service+'/privacy'})]);
 await client.query(`UPDATE public.forms SET is_open=true,data=coalesce(data,'{}')||'{"analytics":{"enabled":true}}' WHERE link='embedded-synthetic'`);
 await client.query(`INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(1,true,1,'fixture','managed consent E2E') ON CONFLICT(organization) DO UPDATE SET enabled=true`);
 await client.query(`INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,collector_origins,revision,operator,reason) VALUES(1,'https://cms-consent-unit.pages.dev','gtm-v1',$1,'{}',1,'fixture','managed consent E2E') ON CONFLICT(unit) DO UPDATE SET parent_origins=EXCLUDED.parent_origins`,[sites]);
 await client.query(`INSERT INTO public.unit_users(unit,"user",is_manager,is_editor_view) VALUES(1,$1,true,true) ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true,is_editor_view=true`,[actor]);
 await client.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[actor]);
 const scope=(await client.query('SELECT public.get_unit_website_consent_bindings(1) v')).rows[0].v;
 const prior=scope.bindings.find(b=>b.websiteOrigin===site);
 const config=platform==='wix' ? {provider:'wix',consentValidFrom:new Date(Date.now()-86400000).toISOString(),maxAgeSeconds:86400}
  : {provider:'cookieconsent',revision:7,categories:{analytics:'statistika návštěv',marketing:'reklama'}};
 const saved=(await client.query('SELECT public.save_unit_website_consent_binding(1,$1,$2,$3::jsonb,$4,$5,true) v',[site,platform,JSON.stringify(config),prior?.version??0,scope.consentRevision])).rows[0].v;
 const binding=saved.bindings.find(b=>b.websiteOrigin===site);
 const exported=(await client.query('SELECT public.export_unit_website_consent_binding($1,$2) v',[binding.id,binding.version])).rows[0].v;
 await client.query('COMMIT');
 const file=path.join(fixture,'fixture-state.json');const state=JSON.parse(fs.readFileSync(file,'utf8'));state.exports[site]=exported;fs.writeFileSync(file,JSON.stringify(state));
 fs.writeFileSync(path.join(fixture,'integrations',platform==='joomla'?'joomla':'wordpress','tests/journey-export.json'),JSON.stringify(exported));
 console.log(JSON.stringify({actor,binding:exported.binding}));
} catch(error){await client.query('ROLLBACK');throw error;}finally{await client.end();}

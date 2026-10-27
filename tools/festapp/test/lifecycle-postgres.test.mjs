import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setup} from './finance-fixtures.mjs';
import {denied} from './form-fixtures.mjs';
import {invokeLifecycleOperation} from '../src/operations/lifecycle.mjs';
const command=(s,action,id,payload={})=>s.db.query('select start_occasion_lifecycle($1,$2,$3,$4,$5,$6,$7) value',[s.f.unit,s.f.org,s.f.occasion,action,id,payload.targetUnit??null,'en']).then(r=>r.rows[0].value);
async function seedMedia(s){await s.db.query('RESET ROLE');await s.db.query("update occasions set data=data||'{\"image\":\"https://img.festapp.net/images/source.jpg\",\"client_sync_v1\":false}',features='[{\"code\":\"ticket\",\"background\":\"https://img.festapp.net/images/source.jpg\"}]' where id=$1",[s.f.occasion]);await s.db.query('SET LOCAL ROLE authenticated');}
test('one canonical database copy survives response loss; immutable media steps resume without duplicate gallery records',async t=>{
 const s=await setup(t);await seedMedia(s);const id=randomUUID();const started=await command(s,'copy',id);const job=started.data.mediaJob;assert.equal(job.state,'pending');assert.equal(job.media.length,2);assert.equal(job.media[0].target,job.media[1].target);
 assert.equal((await command(s,'copy',id)).data.occasionId,started.data.occasionId);
 await denied(s.db,'select finish_occasion_media_job($1)',[id],'55000');
 for(const index of [0,0,1])await s.db.query('select record_occasion_media_step($1,$2)',[id,index]);
 const complete=(await s.db.query('select finish_occasion_media_job($1) value',[id])).rows[0].value;assert.equal(complete.state,'complete');
 assert.deepEqual((await s.db.query('select finish_occasion_media_job($1) value',[id])).rows[0].value,complete);
 await s.db.query('RESET ROLE');const saved=(await s.db.query('select data,features from occasions where id=$1',[job.occasionId])).rows[0];assert.equal(saved.data.image,job.media[0].target);assert.equal(saved.features.find(f=>f.code==='ticket').background,job.media[0].target);
 assert.equal(Number((await s.db.query('select count(*) n from images where occasion=$1 and link=$2',[job.occasionId,job.media[0].target])).rows[0].n),1);
});
test('resumed media preserves newer user-selected images and unrelated settings; gallery presets are not copied',async t=>{
 const s=await setup(t);await seedMedia(s);await s.db.query('RESET ROLE');await s.db.query("update occasions set features='[{\"code\":\"ticket\",\"background\":\"https://img.festapp.net/ticket-presets/v1/default.jpg\"}]' where id=$1",[s.f.occasion]);await s.db.query('SET LOCAL ROLE authenticated');
 const id=randomUUID();const job=(await command(s,'copy',id)).data.mediaJob;assert.equal(job.media.length,1);
 await s.db.query('RESET ROLE');await s.db.query("update occasions set data=data||'{\"image\":\"https://img.festapp.net/images/newer.jpg\",\"unrelated\":\"keep\"}' where id=$1",[job.occasionId]);await s.db.query('SET LOCAL ROLE authenticated');
 await s.db.query('select record_occasion_media_step($1,0)',[id]);await s.db.query('select finish_occasion_media_job($1)',[id]);await s.db.query('RESET ROLE');const data=(await s.db.query('select data from occasions where id=$1',[job.occasionId])).rows[0].data;assert.equal(data.image,'https://img.festapp.net/images/newer.jpg');assert.equal(data.unrelated,'keep');
});
test('lifecycle scope, immutable payload and role loss are checked before replay or another asset step',async t=>{
 const s=await setup(t);await seedMedia(s);const id=randomUUID();const job=(await command(s,'copy',id)).data.mediaJob;
 await denied(s.db,'select start_occasion_lifecycle($1,$2,$3,\'copy\',$4,null,\'cs\')',[s.f.unit,s.f.org,s.f.occasion,id],'22023');
 await denied(s.db,'select start_occasion_lifecycle($1,$2,$3,\'copy\',$4,null,\'en\')',[s.f.unit,s.f.org+999999,s.f.occasion,randomUUID()]);
 await s.db.query('RESET ROLE');await s.db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[s.f.unit,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 await denied(s.db,'select record_occasion_media_step($1,0)',[id]);await denied(s.db,'select get_occasion_media_job($1)',[id]);
});
test('canonical deletion replays its exact tombstone and retains detached blobs just as the current UI',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');await s.db.query("update occasions set data=data||'{\"client_sync_v1\":false}' where id=$1",[s.f.occasion]);await s.db.query("insert into images(link,occasion) values('https://img.festapp.net/images/retain.jpg',$1)",[s.f.occasion]);await s.db.query('SET LOCAL ROLE authenticated');
 const id=randomUUID();const first=await command(s,'delete',id);assert.equal(first.data.mediaJob.assetDisposition,'detached-retained');assert.equal((await command(s,'delete',id)).data.occasionId,s.f.occasion);
 await s.db.query('RESET ROLE');assert.equal(Number((await s.db.query('select count(*) n from occasions where id=$1',[s.f.occasion])).rows[0].n),0);assert.equal((await s.db.query("select occasion from images where link='https://img.festapp.net/images/retain.jpg'")).rows[0].occasion,null);
});
test('SDK executor returns a committed pending copy when the Worker response is lost',async t=>{
 const s=await setup(t);await seedMedia(s);const client={...s.client,auth:{getSession:async()=>({data:{session:{access_token:'fixture-ordinary-jwt'}},error:null})}};
 const owner={...s.owner,delegatedUnitContext:async(_client,unitId)=>{assert.equal(unitId,s.f.unit);return{organizationId:s.f.org,unitId};},lifecycleFetch:async()=>{throw new Error('lost Worker response');}};
 const args={occasionId:s.f.occasion,targetUnitId:s.f.unit,commandId:randomUUID(),locale:'en'};const first=await invokeLifecycleOperation(owner,client,'occasions.copy',args);assert.equal(first.state,'pending');assert.equal(first.assetDisposition,'copy-pending');assert.equal((await invokeLifecycleOperation(owner,client,'occasions.copy',args)).occasionId,first.occasionId);
});

test('the scoped finalizer preserves the real current source/draft/materialization/rollback contract',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');
 await s.db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 await s.db.query(`CREATE FUNCTION public.test_finalize_scoped(p_id uuid,p_revision bigint,p_command uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
 DECLARE d public.occasion_setup_drafts; sources jsonb;
 BEGIN SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('occasionId',x::bigint,'unitId',d.unit)),'[]') INTO sources FROM (SELECT DISTINCT x FROM unnest(ARRAY[d.data->>'sourceId',d.data->>'formSourceOccasionId',d.data->>'blueprintSourceOccasionId']) x WHERE nullif(x,'') IS NOT NULL) selected;
 RETURN public.manage_occasion_setup_authoring(d.unit,d.organization,p_id,p_revision,p_command,sources); END $$;
 GRANT EXECUTE ON FUNCTION public.test_finalize_scoped(uuid,bigint,uuid) TO authenticated;`);
 const original=await readFile(new URL('../../../database/tests/occasion_setup/finalize_test.sql',import.meta.url),'utf8');
 await s.db.query(original.replaceAll('public.finalize_occasion_setup_draft(','public.test_finalize_scoped('));
});

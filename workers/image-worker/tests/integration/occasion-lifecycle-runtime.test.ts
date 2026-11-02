/** Real workerd HTTP/R2 and canonical SQL; the outbound RPC adapter binds a
 * fixture actor directly in local PostgreSQL instead of running GoTrue/PostgREST.
 * No remote service or production data is used. */
import {afterAll, beforeAll, describe, expect, it} from 'vitest';
import {build} from 'esbuild';
import {convertV4MiniflareOptions, Miniflare} from 'miniflare';
import {Client} from 'pg';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';

const databaseUrl = process.env.IMAGE_LIFECYCLE_DATABASE_URL;
if (databaseUrl && !['localhost', '127.0.0.1', '::1', '[::1]'].includes(new URL(databaseUrl).hostname)) {
  throw new Error('IMAGE_LIFECYCLE_DATABASE_URL must select a disposable local database');
}

describe.skipIf(!databaseUrl)('occasion copy/media/delete across workerd and SQL', () => {
  const db = new Client({connectionString: databaseUrl});
  let runtime: Miniflare;
  let org: number, unit: number, source: number;
  const command = randomUUID();
  const sourceUrl = 'https://img.festapp.net/images/lifecycle-fixture.png';
  const bytes = new Uint8Array([137,80,78,71,13,10,26,10]);
  let rpcCalls = 0;
  let redirectRpc = false;
  const signatures: Record<string, string[]> = {
    get_occasion_media_job: ['p_command_id'],
    record_occasion_media_step: ['p_command_id', 'p_index'],
    finish_occasion_media_job: ['p_command_id'],
    admit_image_upload_v1: ['p_bytes', 'p_occasion_id', 'p_unit_id'],
    admit_image_storage_v1: ['p_bytes', 'p_occasion_id', 'p_unit_id'],
  };
  beforeAll(async () => {
    await db.connect();
    await db.query('BEGIN');
    await db.query(readFileSync('../../database/tests/helpers/assertions.sql', 'utf8'));
    // Exercise the final canonical deletion owner without changing the local baseline.
    await db.query(readFileSync('../../database/functions/others/delete_occasion.sql', 'utf8'));
    const actorName = `media_${command.replaceAll('-', '')}`;
    await db.query('SELECT create_user_for_test($1,$2)', [actorName, `${actorName}@test.local`]);
    const actor = (await db.query('SELECT get_user_id($1) AS id', [actorName])).rows[0].id;
    org = (await db.query("INSERT INTO public.organizations(title) VALUES('Worker lifecycle fixture') RETURNING id")).rows[0].id;
    await db.query('UPDATE public.user_info SET organization=$1 WHERE id=$2', [org, actor]);
    unit = (await db.query("INSERT INTO public.units(title,organization) VALUES('Worker lifecycle fixture',$1) RETURNING id", [org])).rows[0].id;
    await db.query('INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES($1,$2,true,true)', [unit, actor]);
    source = (await db.query(`INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,data,features)
      VALUES($1,$2,'Source',$3,now(),now()+interval '1 day',$4,$5) RETURNING id`,
      [org, unit, `runtime-${command}`, {image: sourceUrl}, JSON.stringify([{code:'ticket',is_enabled:true,background:sourceUrl}])] )).rows[0].id;
    await db.query('INSERT INTO public.scanner_settings(occasion_id,config) VALUES($1,public.scanner_default_settings_internal($1))',[source]);
    await db.query("INSERT INTO public.inventory_pools(title,occasion,sellable_capacity) VALUES('Capacity',$1,17)", [source]);
    await db.query("SELECT set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub',$1,true)", [actor]);
    const bundle = await build({entryPoints:['src/index.ts'],bundle:true,write:false,format:'esm',platform:'browser'});
    runtime = new Miniflare(convertV4MiniflareOptions({
      modules:true, script:bundle.outputFiles[0].text, compatibilityDate:'2025-01-01',
      bindings:{SUPABASE_URL:'https://api.festapp.net',SUPABASE_ANON_KEY:'fixture'},
      r2Buckets:['IMAGES_BUCKET','IMAGES_PRIVATE_BUCKET'],
      outboundService:async (request) => {
        rpcCalls++;
        expect(new URL(request.url).origin).toBe('https://api.festapp.net');
        if (redirectRpc) return new Response(null,{status:307,headers:{Location:'https://untrusted.invalid/rpc'}});
        expect(request.headers.get('Authorization')).toBe('Bearer fixture-actor');
        const name = new URL(request.url).pathname.split('/').pop()!;
        const keys = signatures[name];
        if (!keys) throw new Error(`Unexpected RPC: ${name}`);
        const args = await request.json() as Record<string, unknown>;
        const result = await db.query(`SELECT public.${name}(${keys.map((k,i)=>`${k} => $${i+1}`).join(',')}) AS value`,keys.map(k=>args[k]));
        return Response.json(result.rows[0].value);
      },
    }));
    const bucket = await runtime.getR2Bucket('IMAGES_BUCKET');
    await bucket.put('images/lifecycle-fixture.png',bytes,{httpMetadata:{contentType:'image/png'}});
  }, 30_000);
  afterAll(async () => {
    await runtime?.dispose();
    await db.query('ROLLBACK');
    await db.end();
  });
  const resume = (intent = command) => runtime.dispatchFetch('https://image-api.festapp.net/occasion-lifecycle', {
    method:'POST',headers:{Authorization:'Bearer fixture-actor','Content-Type':'application/json'},
    body:JSON.stringify({projectId:'default',commandId:intent}),
  });
  it('rejects RPC redirects without forwarding the actor token', async () => {
    redirectRpc = true;
    const before = rpcCalls;
    try { expect((await resume()).status).toBe(503); } finally { redirectRpc = false; }
    expect(rpcCalls - before).toBe(1);
  });
  it('copies actual object bytes, applies both URLs, replays, then deletes without touching the source', async () => {
    const started = (await db.query("SELECT public.start_occasion_lifecycle($1,$2,$3,'copy',$4) AS value", [unit,org,source,command])).rows[0].value;
    const copied = started.data.occasionId;
    expect(started.data.mediaJob.media).toHaveLength(2);
    const response = await resume();
    expect(await response.text()).toContain('complete');
    expect(response.status).toBe(200);
    expect(rpcCalls).toBeGreaterThan(0);
    const row = (await db.query('SELECT data,features FROM public.occasions WHERE id=$1',[copied])).rows[0];
    expect(row.data.image).toMatch(/\/images\/lifecycle\//);
    expect(row.features[0].background).toBe(row.data.image);
    const bucket = await runtime.getR2Bucket('IMAGES_BUCKET');
    const object = await bucket.get(new URL(row.data.image).pathname.slice(1));
    expect(new Uint8Array(await object!.arrayBuffer())).toEqual(bytes);
    expect((await resume()).status).toBe(200);
    await db.query("SELECT public.start_occasion_lifecycle($1,$2,$3,'delete',$4)",[unit,org,copied,randomUUID()]);
    expect((await db.query('SELECT id FROM public.occasions WHERE id=$1',[copied])).rowCount).toBe(0);
    expect((await db.query('SELECT data FROM public.occasions WHERE id=$1',[source])).rows[0].data.image).toBe(sourceUrl);
    expect(await bucket.get('images/lifecycle-fixture.png')).not.toBeNull();
    // Empty manifests still complete successfully through the actual runtime.
    await db.query("UPDATE public.occasions SET data='{}',features='[]' WHERE id=$1",[source]);
    const emptyCommand = randomUUID();
    const emptyCopy = (await db.query("SELECT public.start_occasion_lifecycle($1,$2,$3,'copy',$4) AS value",[unit,org,source,emptyCommand])).rows[0].value;
    expect(emptyCopy.data.mediaJob.state).toBe('complete');
    expect((await resume(emptyCommand)).status).toBe(200);
    await db.query("SELECT public.start_occasion_lifecycle($1,$2,$3,'delete',$4)",[unit,org,emptyCopy.data.occasionId,randomUUID()]);
  });
});

import {build} from 'esbuild';
import {convertV4MiniflareOptions, Miniflare} from 'miniflare';
import pg from 'pg';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';

/** Real workerd, R2, native Images processing and local GoTrue/PostgREST.
 * Only the canonical backend's outbound transport is redirected to the guarded
 * disposable stack. Production worker configuration and authorization stay intact. */
export async function startLocalUploadRuntime(databaseUrl: string, supabaseUrl: string, anonKey: string) {
  if (!databaseUrl || !supabaseUrl || !anonKey)
    throw new Error('Local DATABASE_URL, SUPABASE_URL and SUPABASE_ANON_KEY are required');
  for (const value of [databaseUrl, supabaseUrl]) {
    if (!['127.0.0.1', 'localhost'].includes(new URL(value).hostname))
      throw new Error('Image integration requires a disposable loopback backend');
  }
  const db = new pg.Client({connectionString: databaseUrl});
  await db.connect();
  const marker = await db.query('SELECT project FROM festapp_test_support.disposable_environment');
  if (!marker.rows[0]?.project?.startsWith('festapp-')) {
    await db.end();
    throw new Error('Missing disposable Festapp database identity');
  }
  const organization = (await db.query("INSERT INTO public.organizations(title) VALUES('Image integration fixture') RETURNING id")).rows[0].id;
  const unit = (await db.query("INSERT INTO public.units(title,organization) VALUES('Image integration fixture',$1) RETURNING id", [organization])).rows[0].id;
  const occasion = (await db.query(`INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
    VALUES($1,$2,'Image integration fixture',$3,now(),now()+interval '1 day') RETURNING id`, [organization,unit,`image-test-${randomUUID()}`])).rows[0].id;
  const bundle = await build({entryPoints:['src/index.ts'],bundle:true,write:false,format:'esm',platform:'browser'});
  const options = convertV4MiniflareOptions({
    modules:true, script:bundle.outputFiles[0].text, compatibilityDate:'2025-01-01',
    bindings:{SUPABASE_URL:'https://api.festapp.net',SUPABASE_ANON_KEY:anonKey,
      CF_ZONE_ID:'local-fixture',CF_CACHE_PURGE_TOKEN:'local-fixture'},
    r2Buckets:['IMAGES_BUCKET','IMAGES_PRIVATE_BUCKET','IMAGES_BUCKET_AKHWEB'],
    outboundService:async request => {
      const target = new URL(request.url);
      // Cloudflare's global purge transport is the only provider stub. Apply
      // its requested invalidation to real local Cache API entries instead.
      if (target.href === 'https://api.cloudflare.com/client/v4/zones/local-fixture/purge_cache') {
        if (request.method !== 'POST' || request.headers.get('Authorization') !== 'Bearer local-fixture')
          throw new Error('Invalid local cache-purge request');
        const {files} = await request.json() as {files:string[]};
        const cache = (await runtime.getCaches()).default;
        for (const file of files) {
          if (new URL(file).origin !== 'https://img.festapp.net') throw new Error('Unexpected cache-purge origin');
          await cache.delete(file);
        }
        return Response.json({success:true});
      }
      if (target.origin !== 'https://api.festapp.net') throw new Error(`Unexpected image integration egress: ${target.origin}`);
      const local = new URL(target.pathname + target.search, supabaseUrl);
      // Node fetch serializes a new body across the workerd boundary. Let it
      // compute Content-Length instead of forwarding the transport header.
      const headers = new Headers(request.headers);
      headers.delete('content-length');
      return globalThis.fetch(local, {
        method:request.method, headers:Object.fromEntries(headers),
        body:['GET','HEAD'].includes(request.method) ? undefined : await request.arrayBuffer(),
        redirect:'manual',
      });
    },
  });
  options.workers[0].config.env.IMAGES = {type:'images'};
  options.workers[0].config.env.IMAGE_READ_MISS_BUDGET = {
    type:'rate-limit',namespace:'local-image-integration',simple:{limit:1000,period:60},
  };
  const runtime = new Miniflare(options);
  return {
    organization, occasion,
    async fetch(input: string | URL, init?: RequestInit): Promise<Response> {
      const url = new URL(input);
      if (url.origin === new URL(supabaseUrl).origin) return globalThis.fetch(url, init);
      if (!['https://image-api.festapp.net','https://img.festapp.net'].includes(url.origin))
        throw new Error(`Unexpected image integration request: ${url.origin}`);
      // Serialize native FormData before crossing Miniflare's Request boundary.
      const request = new Request(url, init);
      return runtime.dispatchFetch(url, {
        method:request.method, headers:request.headers,
        body:['GET','HEAD'].includes(request.method) ? undefined : await request.arrayBuffer(),
      }) as unknown as Promise<Response>;
    },
    async photo() {
      const images = await runtime.getImagesBinding('IMAGES');
      const bytes = readFileSync('../../assets/brand/vstupenky-online/concepts/chatgpt-selected-concept.png');
      const output = await images.input(new Response(bytes).body!).output({format:'image/jpeg',quality:95});
      return output.response().arrayBuffer();
    },
    async dispose() {
      try { await runtime.dispose(); }
      finally {
        try {
          await db.query('DELETE FROM public.images WHERE occasion=$1', [occasion]);
          await db.query('DELETE FROM public.occasions WHERE id=$1', [occasion]);
          await db.query('DELETE FROM public.units WHERE id=$1', [unit]);
          await db.query('DELETE FROM public.organizations WHERE id=$1', [organization]);
        } finally { await db.end(); }
      }
    },
  };
}

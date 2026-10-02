// Loopback-only fixture host. Uses the production Edge handler and PDF renderer.
// No production authentication, data access or writes are performed here.
import { PDFDocument } from 'npm:pdf-lib';
import { serveDir } from 'jsr:@std/http/file-server';
import { handlePreview } from '../../../supabase/functions/preview-ticket-layout/handler.ts';
import { fontBytes, fontMetrics } from '../../../supabase/functions/_shared/ticketGeneration.ts';
const root = Deno.args[0] ?? '/tmp/festapp-ticket-editor-web';
const font = await fontBytes(), metrics = fontMetrics(font);
const catalog = JSON.parse(await Deno.readTextFile('test/fixtures/ticket_layout/historical/catalog.json'));
const images = new Map<string, Uint8Array>();
for (const item of catalog) if (item.image) {
  const path = `fixtures/ticket_layout/historical/${item.image}`;
  images.set(`https://img.festapp.net/__local_preview__/${encodeURIComponent(path)}`,
    await Deno.readFile(`test/${path}`));
}
const uploaded = new Map<string, Uint8Array>();
Deno.serve({ hostname: '127.0.0.1', port: 8769 }, async req => {
  const url = new URL(req.url);
  if (!['localhost:8769','127.0.0.1:8769'].includes(url.host)) return new Response('Invalid host', { status: 403 });
  if (url.pathname.startsWith('/local-images/') && req.method === 'GET') {
    const bytes = uploaded.get(url.pathname.slice('/local-images/'.length));
    return bytes ? new Response(new Uint8Array(bytes).buffer, {headers:{'Content-Type':bytes[0]===137?'image/png':'image/jpeg'}}) : new Response('Not found',{status:404});
  }
  if (url.pathname === '/api/ticket-background') {
    const origin=req.headers.get('origin');
    if (origin && origin!==url.origin) return new Response('Invalid origin',{status:403});
    if(req.method!=='POST' || req.headers.get('content-type')!=='application/octet-stream') return new Response('Invalid upload',{status:400});
    if(uploaded.size>=20) return new Response('Local image limit reached',{status:413});
    try {
      const chunks:Uint8Array[]=[]; let length=0;
      for await(const chunk of req.body!) {length+=chunk.length;if(length>4_000_000)return new Response('Too large',{status:413});chunks.push(chunk);}
      const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
      const doc=await PDFDocument.create();const image=bytes[0]===137?await doc.embedPng(bytes):await doc.embedJpg(bytes);
      if(image.width>4096||image.height>4096) return new Response('Image too large',{status:400});
      const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(b=>b.toString(16).padStart(2,'0')).join('');
      const path=`local-images/${hash}`;
      uploaded.set(hash,bytes);images.set(`https://img.festapp.net/__local_preview__/${encodeURIComponent(path)}`,bytes);
      return Response.json({background:path});
    } catch {return new Response('Invalid image',{status:400});}
  }
  if (url.pathname === '/api/ticket-preview') {
    const origin = req.headers.get('origin');
    if (origin && origin !== url.origin) return new Response('Invalid origin', { status: 403 });
    if (req.method !== 'POST' || !req.headers.get('content-type')?.startsWith('application/json')) return new Response('JSON POST required', { status: 405 });
    return await handlePreview(req, {
      authorize: async (header, id) => header === 'Bearer local-preview' && id === 1,
      occasion: async () => ({id:1, title:'Slavnostní večer', start_time:'2026-11-20T18:00:00Z', data:{place_name:'Společenský sál'}, features:[]}),
      resources: async (_occasion, feature) => {
        const background = feature.background ? images.get(feature.background) : undefined;
        if (feature.background && !background) throw new Error('Unknown local background');
        return {font, metrics, background};
      },
    });
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return new Response('Method not allowed', { status: 405 });
  return serveDir(req, { fsRoot: root, quiet: true, showDirListing: false });
});

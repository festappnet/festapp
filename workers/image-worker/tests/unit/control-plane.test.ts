import { afterEach, describe, expect, it, vi } from 'vitest';
import { handleCors } from '../../src/cors';
import { handleDelete } from '../../src/delete';
import { handleUpload } from '../../src/upload';
import type { Env } from '../../src/types';
import worker from '../../src/index';

function bucket() {
  return { put: vi.fn(), delete: vi.fn(), get: vi.fn(), head: vi.fn() } as unknown as R2Bucket;
}

function env(): Env {
  return {
    IMAGES_BUCKET: bucket(), IMAGES_BUCKET_A: bucket(),
    IMAGES_BUCKET_AKHWEB: bucket(),
    IMAGES_PRIVATE_BUCKET: bucket(), IMAGES_PRIVATE_BUCKET_A: bucket(),
    SUPABASE_URL: 'https://default.supabase.co', SUPABASE_ANON_KEY: 'server-default',
    SUPABASE_URL_A: 'https://a.supabase.co', SUPABASE_ANON_KEY_A: 'server-a',
    SUPABASE_URL_AKHWEB: 'https://akh.supabase.co', SUPABASE_ANON_KEY_AKHWEB: 'server-akh',
    R2_ACCESS_KEY_ID: 'id', R2_SECRET_ACCESS_KEY: 'secret', CF_ACCOUNT_ID: 'account',
    CF_ZONE_ID: 'zone', CF_CACHE_PURGE_TOKEN: 'purge-token',
    CONTROL_ALLOWED_ORIGINS: 'https://app.example',
  };
}

afterEach(() => vi.unstubAllGlobals());

describe('control plane', () => {
  it('uses exact CORS origins and Vary', () => {
    const configured = env();
    const allowed = handleCors(new Request('https://image-api.festapp.net/upload', {
      method: 'OPTIONS', headers: { Origin: 'https://app.example' },
    }), configured);
    expect(allowed.status).toBe(204);
    expect(allowed.headers.get('Access-Control-Allow-Origin')).toBe('https://app.example');
    expect(allowed.headers.get('Vary')).toBe('Origin');
    expect(handleCors(new Request('https://image-api.festapp.net/upload', {
      method: 'OPTIONS', headers: { Origin: 'https://evil.example' },
    }), configured).status).toBe(403);
  });

  it('allows credential-free public image reads from any web origin', async () => {
    const configured = env();
    const origin = 'https://hvezdamorska.netlify.app';

    const preflight = await worker.fetch(new Request('https://a.img.festapp.net/images/236/x.webp', {
      method: 'OPTIONS', headers: { Origin: origin },
    }), configured);
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get('Access-Control-Allow-Origin')).toBe('*');
    expect(preflight.headers.get('Access-Control-Allow-Methods')).toBe('GET, HEAD, OPTIONS');

    const response = await worker.fetch(new Request('https://a.img.festapp.net/images/236/x.webp', {
      headers: { Origin: origin },
    }), configured);
    expect(response.status).toBe(404);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('*');
  });

  it('does not make private routes public on a public compatibility host', async () => {
    const response = await worker.fetch(new Request('https://a.img.festapp.net/private/236/x.webp', {
      method: 'OPTIONS', headers: { Origin: 'https://untrusted.example' },
    }), env());
    expect(response.status).toBe(403);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('compensates the public R2 write when DB persistence fails', async () => {
    const configured = env();
    vi.stubGlobal('fetch', vi.fn()
      .mockResolvedValueOnce(new Response('true', { status: 200 }))
      .mockResolvedValueOnce(new Response('failed', { status: 500 })));
    const form = new FormData();
    form.set('file', new File([new Uint8Array([1, 2, 3])], 'x.jpg', { type: 'image/jpeg' }));
    form.set('occasionId', '42');
    form.set('projectId', 'default');
    form.set('anonKey', 'attacker-key');
    const response = await handleUpload(new Request('https://image-api.festapp.net/upload', {
      method: 'POST', headers: { Authorization: 'Bearer jwt' }, body: form,
    }), configured);
    expect(response.status).toBe(502);
    expect(configured.IMAGES_BUCKET.put).toHaveBeenCalledOnce();
    expect(configured.IMAGES_BUCKET.delete).toHaveBeenCalledOnce();
    expect((fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].headers.apikey).toBe('server-default');
  });

  it('uses the AKH role contract and skips Festapp image records', async () => {
    const configured = env();
    const mockedFetch = vi.fn().mockResolvedValueOnce(new Response('true', { status: 200 }));
    vi.stubGlobal('fetch', mockedFetch);
    const form = new FormData();
    form.set('file', new File([new Uint8Array([1, 2, 3])], 'x.jpg', { type: 'image/jpeg' }));
    form.set('projectId', 'akhweb');
    form.set('prefix', 'content');
    form.set('folder', 'gallery');
    const response = await handleUpload(new Request('https://image-api.festapp.net/upload', {
      method: 'POST', headers: { Authorization: 'Bearer jwt' }, body: form,
    }), configured);
    const body = await response.json() as { url: string; key: string };
    expect(response.status).toBe(200);
    expect(body.url).toMatch(/^https:\/\/akh\.img\.festapp\.net\/content\/gallery\//);
    expect(body.key).toMatch(/^content\/gallery\//);
    expect(mockedFetch).toHaveBeenCalledOnce();
    expect(mockedFetch.mock.calls[0][0]).toContain('/get_can_manage_images');
    expect(configured.IMAGES_BUCKET_AKHWEB.put).toHaveBeenCalledOnce();
  });

  it('authorizes AKH delete without Festapp image-record RPCs', async () => {
    const configured = env();
    const mockedFetch = vi.fn()
      .mockResolvedValueOnce(new Response('true', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ success: true }), { status: 200 }));
    vi.stubGlobal('fetch', mockedFetch);
    const link = 'https://akh.img.festapp.net/content/gallery/x.jpg';
    const response = await handleDelete(new Request('https://image-api.festapp.net/delete', {
      method: 'POST', headers: { Authorization: 'Bearer jwt', 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectId: 'akhweb', links: [link] }),
    }), configured);
    expect(response.status).toBe(200);
    expect(configured.IMAGES_BUCKET_AKHWEB.delete).toHaveBeenCalledWith('content/gallery/x.jpg');
    expect(mockedFetch).toHaveBeenCalledTimes(2);
    expect(mockedFetch.mock.calls[0][0]).toContain('/get_can_manage_images');
  });

  it('rejects malformed key-only delete and cross-project stored URLs before mutation', async () => {
    const configured = env();
    const send = (body: unknown) => handleDelete(new Request('https://image-api.festapp.net/delete', {
      method: 'POST', headers: { Authorization: 'Bearer jwt', 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }), configured);
    expect((await send({ projectId: 'default', key: 'images/../x.jpg' })).status).toBe(400);
    expect((await send({ projectId: 'default', links: ['https://a.img.festapp.net/images/1/x.jpg'] })).status).toBe(400);
    expect(configured.IMAGES_BUCKET.delete).not.toHaveBeenCalled();
  });

  it('authorizes the temporary legacy public-key delete as an exact stored link', async () => {
    const configured = env();
    const link = 'https://img.festapp.net/images/1/x.jpg';
    const mockedFetch = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify([{ link }]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ success: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('null', { status: 200 }));
    vi.stubGlobal('fetch', mockedFetch);
    const response = await handleDelete(new Request('https://img.festapp.net/delete', {
      method: 'POST', headers: { Authorization: 'Bearer jwt', 'Content-Type': 'application/json' },
      body: JSON.stringify({ supabaseUrl: 'https://default.supabase.co', key: 'images/1/x.jpg' }),
    }), configured);
    expect(response.status).toBe(200);
    expect(mockedFetch.mock.calls[0][0]).toContain('/authorize_image_deletion');
    expect(JSON.parse(mockedFetch.mock.calls[0][1].body)).toEqual({ p_links: [link] });
  });

  it('deletes, purges varied images by source URL, then removes the record', async () => {
    const configured = env();
    const link = 'https://img.festapp.net/images/1/x.jpg';
    const mockedFetch = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify([{ link }]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ success: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('null', { status: 200 }));
    vi.stubGlobal('fetch', mockedFetch);
    const response = await handleDelete(new Request('https://image-api.festapp.net/delete', {
      method: 'POST', headers: { Authorization: 'Bearer jwt', 'Content-Type': 'application/json' },
      body: JSON.stringify({ projectId: 'default', links: [link] }),
    }), configured);
    expect(response.status).toBe(200);
    expect(configured.IMAGES_BUCKET.delete).toHaveBeenCalledWith('images/1/x.jpg');
    expect(JSON.parse(mockedFetch.mock.calls[1][1].body)).toEqual({ files: [link] });
    expect(mockedFetch.mock.calls[2][0]).toContain('/remove_image_records');
  });
});

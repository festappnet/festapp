import { webcrypto } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { handleTicketFonts } from '../../src/ticket-fonts';
import worker from '../../src/index';
import type { Env } from '../../src/types';

vi.stubGlobal('crypto', webcrypto);
const secret = 'font-only-private-service-capability-0123456789';
const bytes = new Uint8Array([0, 1, 2, 3]);
const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
const key = `sha256/${hash}.ttf`;
const url = `https://image-api.festapp.net/service/ticket-fonts/${key}`;
const put = vi.fn(), get = vi.fn();
const env = { TICKET_FONT_SERVICE_SECRET: secret, IMAGES_PRIVATE_BUCKET: { put, get }, IMAGES_BUCKET: { get: vi.fn() } } as unknown as Env;
const request = (method = 'GET', token = secret, path = url) => new Request(path, {
  method, headers: { Authorization: `Bearer ${token}`, ...(method === 'PUT' ? { 'Content-Length': String(bytes.length) } : {}) },
  body: method === 'PUT' ? bytes : undefined,
});

beforeEach(() => { vi.clearAllMocks(); });
describe('service-only immutable font namespace', () => {
  it('fails closed for absent configuration, user tokens and public hosts', async () => {
    expect((await handleTicketFonts(request(), { ...env, TICKET_FONT_SERVICE_SECRET: undefined })).status).toBe(503);
    expect((await handleTicketFonts(request('GET', 'user-jwt'), env)).status).toBe(401);
    expect((await worker.fetch(request('GET', secret, url.replace('image-api', 'img')), env)).status).toBe(404);
    expect(get).not.toHaveBeenCalled();
  });
  it('returns exact private bytes with no-store, and preserves absence', async () => {
    get.mockResolvedValueOnce({ size: bytes.length, body: bytes }).mockResolvedValueOnce(null);
    const response = await handleTicketFonts(request(), env);
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
    expect(response.headers.get('Cache-Control')).toBe('private, no-store');
    expect(get).toHaveBeenCalledWith(`ticket-fonts/${key}`);
    expect((await handleTicketFonts(request(), env)).status).toBe(404);
  });
  it('hash-checks writes and conditionally creates; replay never overwrites', async () => {
    put.mockResolvedValueOnce({}).mockResolvedValueOnce(null);
    expect((await handleTicketFonts(request('PUT'), env)).status).toBe(201);
    expect((await handleTicketFonts(request('PUT'), env)).status).toBe(409);
    expect(put.mock.calls[0][2].onlyIf).toEqual({ etagDoesNotMatch: '*' });
    expect((await handleTicketFonts(request('PUT', secret, url.replace(hash, '0'.repeat(64))), env)).status).toBe(422);
    expect(put).toHaveBeenCalledTimes(2);
  });
  it('denies other namespaces, listing, delete, oversize and length mismatch', async () => {
    expect((await handleTicketFonts(request('DELETE'), env)).status).toBe(405);
    expect((await handleTicketFonts(request('GET', secret, url.replace(key, 'private/secret')), env)).status).toBe(400);
    const oversize = new Request(url, { method: 'PUT', headers: { Authorization: `Bearer ${secret}`, 'Content-Length': String(8 * 1024 * 1024 + 1) }, body: bytes });
    expect((await handleTicketFonts(oversize, env)).status).toBe(413);
    const mismatch = new Request(url, { method: 'PUT', headers: { Authorization: `Bearer ${secret}`, 'Content-Length': '5' }, body: bytes });
    expect((await handleTicketFonts(mismatch, env)).status).toBe(400);
    expect(put).not.toHaveBeenCalled();
  });
});

it('publishes validated prepared metrics only after immutable bytes exist', async () => {
  const {preparedFont} = await import('../../../../supabase/functions/_shared/ticketPreparedFont');
  const sidecar = new TextEncoder().encode(JSON.stringify(await preparedFont(hash,{advances:{'?':1,'ě':.4},ascent:.9,descent:-.2})));
  const head=vi.fn().mockResolvedValue({});
  const scoped={...env,IMAGES_PRIVATE_BUCKET:{get,put,head}} as unknown as Env;
  const path=url.replace('.ttf','.metrics-v1.json');
  const write=(body:Uint8Array,token=secret)=>new Request(path,{method:'PUT',headers:{Authorization:`Bearer ${token}`,'Content-Length':String(body.length)},body});
  put.mockResolvedValueOnce({}).mockResolvedValueOnce(null);
  expect((await handleTicketFonts(write(sidecar),scoped)).status).toBe(201);
  expect((await handleTicketFonts(write(sidecar),scoped)).status).toBe(409);
  expect((await handleTicketFonts(write(sidecar,'user-jwt'),scoped)).status).toBe(401);
  head.mockResolvedValue(null);
  expect((await handleTicketFonts(write(sidecar),scoped)).status).toBe(409);
  expect((await handleTicketFonts(write(new TextEncoder().encode('{}')),scoped)).status).toBe(422);
  expect(get).not.toHaveBeenCalled();
});

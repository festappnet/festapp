import { webcrypto } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { handleTicketBatches } from '../../src/ticket-batches';
import type { Env } from '../../src/types';
vi.stubGlobal('crypto', webcrypto);
const secret='batch-only-private-service-capability-0123456789';
const key=`ba000000-0000-0000-0000-000000000001/${'a'.repeat(64)}/single-001.pdf`;
const url='https://image-api.festapp.net/service/ticket-batches/'+key;
const bytes=new Uint8Array([37,80,68,70]);const put=vi.fn(),get=vi.fn();
const env={TICKET_BATCH_SERVICE_SECRET:secret,IMAGES_PRIVATE_BUCKET:{put,get},IMAGES_BUCKET:{get:vi.fn()}} as unknown as Env;
const request=(method='GET',token=secret,path=url)=>new Request(path,{method,headers:{Authorization:`Bearer ${token}`,...(method==='PUT'?{'Content-Length':String(bytes.length)}:{})},body:method==='PUT'?bytes:undefined});
beforeEach(()=>vi.clearAllMocks());
describe('private immutable batch documents',()=>{
 it('denies missing capability, browser tokens, other hosts and arbitrary keys',async()=>{
  expect((await handleTicketBatches(request(),{...env,TICKET_BATCH_SERVICE_SECRET:undefined})).status).toBe(503);
  expect((await handleTicketBatches(request('GET','user-jwt'),env)).status).toBe(401);
  expect((await handleTicketBatches(request('GET',secret,url.replace('image-api','img')),env)).status).toBe(404);
  expect((await handleTicketBatches(request('GET',secret,url.replace('single-001.pdf','other.pdf')),env)).status).toBe(400);
  expect(get).not.toHaveBeenCalled();expect(put).not.toHaveBeenCalled();
 });
 it('reads exact bytes with no public cache and returns absence',async()=>{
  get.mockResolvedValueOnce({size:bytes.length,body:bytes}).mockResolvedValueOnce(null);
  const r=await handleTicketBatches(request(),env);expect(new Uint8Array(await r.arrayBuffer())).toEqual(bytes);expect(r.headers.get('Cache-Control')).toBe('private, no-store');
  expect(get).toHaveBeenCalledWith('ticket-batches/'+key);expect((await handleTicketBatches(request(),env)).status).toBe(404);
 });
 it('conditionally creates in the private namespace and cannot replace a winner or delete',async()=>{
  put.mockResolvedValueOnce({key}).mockResolvedValueOnce(null);
  expect((await handleTicketBatches(request('PUT'),env)).status).toBe(201);
  expect(put.mock.calls[0][0]).toBe('ticket-batches/'+key);expect(put.mock.calls[0][2].onlyIf).toEqual({etagDoesNotMatch:'*'});
  expect((await handleTicketBatches(request('PUT'),env)).status).toBe(409);
  expect((await handleTicketBatches(request('DELETE'),env)).status).toBe(405);
 });
 it('rejects oversized and dishonest body lengths before writing',async()=>{
  for(const length of ['0',String(17*1024*1024),'3']){
   const r=new Request(url,{method:'PUT',headers:{Authorization:`Bearer ${secret}`,'Content-Length':length},body:bytes});
   expect((await handleTicketBatches(r,env)).status).toBe(413);
  }
  expect(put).not.toHaveBeenCalled();
 });
});

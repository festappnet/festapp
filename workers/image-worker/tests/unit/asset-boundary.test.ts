import { afterEach, expect, it, vi } from 'vitest';
import { handlePublicServe } from '../../src/serve-public';
import { assetKey } from '../../src/asset-key';
import { sourceCacheUrls } from '../../src/purge';
import type { Env } from '../../src/types';

const object = (body: string, type: string) => ({ body, size: body.length, httpEtag: '"hash"', httpMetadata: {contentType:type}, writeHttpMetadata(headers: Headers) {headers.set('Content-Type',type);} });
const get = vi.fn();
const akhGet = vi.fn();
const env = {
  IMAGES_BUCKET: {get}, IMAGES_PRIVATE_BUCKET: {}, IMAGES_BUCKET_AKHWEB: {get:akhGet},
  SUPABASE_URL:'https://api.festapp.net',SUPABASE_ANON_KEY:'default',
  SUPABASE_URL_A:'https://api.festapp.net',SUPABASE_ANON_KEY_A:'a',
  SUPABASE_URL_AKHWEB:'https://akh.example',SUPABASE_ANON_KEY_AKHWEB:'akh',
  IMAGE_READ_MISS_BUDGET:{limit:vi.fn().mockResolvedValue({success:true})},
  IMAGES:{input:vi.fn()},
} as unknown as Env;
afterEach(()=>{vi.clearAllMocks();});

it('preserves both historical R2 URLs when their equal keys have different bytes', async()=>{
  get.mockImplementation(async(key:string)=>object(key.startsWith('imports/a/')?'from-a':'from-default','image/png'));
  expect(await (await handlePublicServe(new Request('https://img.festapp.net/images/same.png'),env)).text()).toBe('from-default');
  expect(await (await handlePublicServe(new Request('https://a.img.festapp.net/images/same.png'),env)).text()).toBe('from-a');
  expect(get.mock.calls.map(call=>call[0])).toEqual(['images/same.png','imports/a/images/same.png']);
  expect(assetKey({id:'a'},'private/file.pdf')).toBe('imports/a/private/file.pdf');
});
it('keeps the independent AKH bucket and its existing content prefixes', async()=>{
  akhGet.mockResolvedValue(object('akh','image/jpeg'));
  expect(await (await handlePublicServe(new Request('https://akh.img.festapp.net/content/gallery/file.jpg'),env)).text()).toBe('akh');
  expect(akhGet).toHaveBeenCalledWith('content/gallery/file.jpg');
  expect(get).not.toHaveBeenCalled();
});
it('serves binary assets byte-for-byte with their MIME, even with image parameters',async()=>{
  get.mockResolvedValue(object('%PDF-original','application/pdf'));
  const response=await handlePublicServe(new Request('https://img.festapp.net/assets/storage/owner/hash?w=300&f=webp'),env);
  expect(await response.text()).toBe('%PDF-original');
  expect(response.headers.get('Content-Type')).toBe('application/pdf');
  expect(env.IMAGES.input).not.toHaveBeenCalled();
});
it('denies private/font namespaces and unregistered physical aliases before bucket reads',async()=>{
  for(const path of ['ticket-fonts/sha256/hash.ttf','imports/a/images/same.png','private/file.pdf']) {
    expect((await handlePublicServe(new Request('https://img.festapp.net/'+path),env)).status).toBe(404);
  }
  expect(get).not.toHaveBeenCalled();
});
it('purges original and every normalized cached query/transform representation',()=>{
  const url='https://a.img.festapp.net/images/same.png';
  const variants=sourceCacheUrls(url);
  expect(variants).toHaveLength(22);
  expect(new Set(variants).size).toBe(22);
  expect(variants).toContain(url+'?w=600&f=auto&q=75&_format=avif');
  expect(variants.some(value=>value.includes('/cdn-cgi/image/width=1200,'))).toBe(true);
  expect(sourceCacheUrls('https://akh.img.festapp.net/content/gallery/file.jpg')).toEqual(['https://akh.img.festapp.net/content/gallery/file.jpg']);
});

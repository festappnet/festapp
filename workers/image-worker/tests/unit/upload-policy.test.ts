import { describe, expect, it, vi } from 'vitest';
import { processUploadImage, resolveUploadPolicy, readUploadForm, MAX_UPLOAD_BODY_BYTES } from '../../src/upload-policy';
import { handleUpload } from '../../src/upload';
import type { Env } from '../../src/types';

function fixture(format = 'image/jpeg', width = 4662, height = 3108, outputs = [128]) {
  let index = 0;
  const output = vi.fn().mockImplementation(async () => ({ response: () => new Response(new Uint8Array(outputs[Math.min(index++, outputs.length - 1)])) }));
  const transform = vi.fn().mockReturnValue({ output });
  const images = { info: vi.fn().mockResolvedValue({ format, fileSize: 100, width, height }), input: vi.fn().mockReturnValue({ transform }) };
  return { env: { IMAGES: images } as unknown as Env, images, transform, output };
}
function policy(profile: string) { const form = new FormData(); form.set('profile', profile); return resolveUploadPolicy(form); }
const file = new File([new Uint8Array([255, 216, 255])], 'source.jpg', { type: 'image/jpeg' });

describe('one server-owned image upload policy', () => {
  it.each([
    ['standard', 1600, 85], ['ticket-background', 1080, 85],
    ['blueprint-background', 3000, 90], ['portrait', 400, 85],
    ['thumbnail', 200, 85], ['banner', 900, 85],
  ])('processes %s using server bounds even for a small encoded file', async (profile, edge, quality) => {
    const f = fixture();
    const result = await processUploadImage(file, policy(String(profile)), f.env);
    expect(f.transform).toHaveBeenCalledWith({ width: edge, height: edge, fit: 'scale-down' });
    expect(f.output).toHaveBeenCalledWith({ format: 'image/jpeg', quality, anim: false });
    expect(result.contentType).toBe('image/jpeg');
    expect(result.extension).toBe('jpg');
  });
  it('preserves PNG alpha through lossless PNG output and enforces its print byte budget', async () => {
    const f = fixture('image/png', 4000, 2000, [3_000_000, 128]);
    const result = await processUploadImage(file, policy('ticket-background'), f.env);
    expect(f.output).toHaveBeenCalledTimes(2);
    expect(f.output).toHaveBeenCalledWith({ format: 'image/png', anim: false });
    expect(f.transform.mock.calls[1][0].width).toBeLessThan(1080);
    expect((result.body as ArrayBuffer).byteLength).toBeLessThanOrEqual(800 * 1024);
  });
  it.each(['image/gif', 'image/webp'])('keeps %s animation in general images and resolves still print artwork on the server', async (format) => {
    const f = fixture(format);
    await processUploadImage(file, policy('standard'), f.env);
    expect(f.output).toHaveBeenCalledWith(expect.objectContaining({ format, anim: true }));
    await processUploadImage(file, policy('ticket-background'), f.env);
    expect(f.output).toHaveBeenLastCalledWith({ format: 'image/png', anim: false });
  });
  it('does not silently store the original when modern processing fails', async () => {
    const f = fixture(); f.output.mockRejectedValue(new Error('transform failed'));
    await expect(processUploadImage(file, policy('standard'), f.env)).rejects.toMatchObject({ code: 'IMAGE_TRANSFORM_FAILED' });
  });
  it('rejects unsupported, oversized and unavailable processing before storage', async () => {
    await expect(processUploadImage(file, policy('standard'), fixture('image/svg+xml').env)).rejects.toMatchObject({ code: 'UNSUPPORTED_IMAGE' });
    await expect(processUploadImage(file, policy('standard'), fixture('image/jpeg', 9000, 9000).env)).rejects.toMatchObject({ code: 'IMAGE_TOO_LARGE' });
    await expect(processUploadImage(file, policy('standard'), {} as Env)).rejects.toMatchObject({ code: 'IMAGE_PROCESSOR_UNAVAILABLE' });
  });
  it('rejects invented profiles and caller overrides of a server profile', () => {
    expect(() => policy('invented')).toThrow('Unknown image upload profile');
    const form = new FormData(); form.set('profile', 'standard'); form.set('maxBytes', '10485760');
    expect(() => resolveUploadPolicy(form)).toThrow('Profile owns image processing options');
  });
  it('retains one explicit legacy adapter for installed clients without a profile', async () => {
    const form = new FormData(); form.set('maxBytes', '10485760');
    const result = await processUploadImage(file, resolveUploadPolicy(form), {} as Env);
    expect(result.contentType).toBe('image/jpeg');
    expect(result.body).toBeInstanceOf(ReadableStream);
  });
  it('bounds multipart reads without trusting Content-Length', async () => {
    const body = new ReadableStream<Uint8Array>({ start(c) { c.enqueue(new Uint8Array(MAX_UPLOAD_BODY_BYTES + 1)); c.close(); } });
    const request = new Request('https://image-api.festapp.net/upload', { method: 'POST', body, headers: { 'Content-Type': 'multipart/form-data; boundary=fixture' }, duplex: 'half' } as RequestInit);
    await expect(readUploadForm(request)).rejects.toMatchObject({ status: 413 });
  });
  it('fails a public upload before the bucket or image-record write when processing fails', async () => {
    const f = fixture(); f.output.mockRejectedValue(new Error('transform failed'));
    const bucket = { put: vi.fn(), delete: vi.fn() };
    const env = { ...f.env, SUPABASE_URL: 'https://api.festapp.net', SUPABASE_ANON_KEY: 'fixture', IMAGES_BUCKET: bucket, IMAGES_PRIVATE_BUCKET: bucket } as unknown as Env;
    const fetchMock = vi.fn().mockImplementation(async () => new Response('true'));
    vi.stubGlobal('fetch', fetchMock);
    try {
      const form = new FormData(); form.set('file', file); form.set('projectId', 'default'); form.set('occasionId', '12'); form.set('profile', 'standard');
      const response = await handleUpload(new Request('https://image-api.festapp.net/upload', { method: 'POST', headers: { Authorization: 'Bearer fixture' }, body: form }), env);
      expect(response.status).toBe(502);
      expect(bucket.put).not.toHaveBeenCalled();
      expect(fetchMock).toHaveBeenCalledTimes(2);
    } finally { vi.unstubAllGlobals(); }
  });
});

import type { Env } from './types';

export const MAX_IMAGE_INPUT_BYTES = 20_000_000;
export const MAX_IMAGE_PIXELS = 40_000_000;
export const MAX_UPLOAD_BODY_BYTES = MAX_IMAGE_INPUT_BYTES + 64 * 1024;

const profiles = {
  standard: { maxEdge: 1600, maxBytes: 1536 * 1024, quality: 85 },
  'ticket-background': { maxEdge: 1600, maxBytes: 2 * 1024 * 1024, quality: 90 },
  'blueprint-background': { maxEdge: 3000, maxBytes: 800 * 1024, quality: 90 },
  portrait: { maxEdge: 400, maxBytes: 200 * 1024, quality: 85 },
  thumbnail: { maxEdge: 200, maxBytes: 80 * 1024, quality: 85 },
  banner: { maxEdge: 900, maxBytes: 800 * 1024, quality: 85 },
} as const;
export type ImageUploadProfile = keyof typeof profiles;
export interface UploadPolicy { maxEdge: number; maxBytes: number; quality: number; profile?: ImageUploadProfile; }
export class ImageProcessingError extends Error {
  constructor(readonly status: number, readonly code: string, message: string, readonly retryable = false) { super(message); }
}

/** One boundary adapter for already released clients. New clients send only profile. */
export function resolveUploadPolicy(form: FormData): UploadPolicy {
  const profile = form.get('profile');
  if (profile !== null) {
    if (typeof profile !== 'string' || !Object.hasOwn(profiles, profile)) {
      throw new ImageProcessingError(400, 'INVALID_IMAGE_PROFILE', 'Unknown image upload profile');
    }
    if (['maxEdge', 'maxBytes', 'quality'].some((key) => form.has(key))) {
      throw new ImageProcessingError(400, 'CONFLICTING_IMAGE_POLICY', 'Profile owns image processing options');
    }
    return { ...profiles[profile as ImageUploadProfile], profile: profile as ImageUploadProfile };
  }
  const number = (key: string, fallback: number) => form.get(key) ? Number(form.get(key)) : fallback;
  const policy = { maxEdge: number('maxEdge', 1200), maxBytes: number('maxBytes', 800 * 1024), quality: number('quality', 70) };
  if (!Number.isInteger(policy.maxEdge) || policy.maxEdge < 1 || policy.maxEdge > 4000 ||
      !Number.isInteger(policy.maxBytes) || policy.maxBytes < 0 || policy.maxBytes > 10 * 1024 * 1024 ||
      !Number.isInteger(policy.quality) || policy.quality < 1 || policy.quality > 100) {
    throw new ImageProcessingError(400, 'INVALID_TRANSFORM_INPUT', 'Upload transform values are out of bounds');
  }
  return policy;
}

/** Bound multipart parsing even when the caller sends no Content-Length. */
export async function readUploadForm(request: Request): Promise<FormData> {
  if (Number(request.headers.get('Content-Length')) > MAX_UPLOAD_BODY_BYTES) {
    throw new ImageProcessingError(413, 'FILE_TOO_LARGE', 'Image upload exceeds 20 MB');
  }
  if (!request.body) throw new ImageProcessingError(400, 'INVALID_FORM_DATA', 'Missing upload body');
  const reader = request.body.getReader();
  let count = 0;
  let tooLarge = false;
  const bounded = new ReadableStream<Uint8Array>({
    async pull(controller) {
      const { value, done } = await reader.read();
      if (done) { controller.close(); reader.releaseLock(); return; }
      count += value.byteLength;
      if (count > MAX_UPLOAD_BODY_BYTES) {
        tooLarge = true;
        controller.error(new Error('Upload body too large'));
        await reader.cancel();
        return;
      }
      controller.enqueue(value);
    },
    cancel: (reason) => reader.cancel(reason),
  });
  try {
    return await new Response(bounded, { headers: { 'Content-Type': request.headers.get('Content-Type') || '' } }).formData();
  } catch {
    throw new ImageProcessingError(tooLarge ? 413 : 400, tooLarge ? 'FILE_TOO_LARGE' : 'INVALID_FORM_DATA',
      tooLarge ? 'Image upload exceeds 20 MB' : 'Invalid form data');
  }
}

export async function processUploadImage(file: File, policy: UploadPolicy, env: Env): Promise<{ body: ReadableStream | ArrayBuffer; contentType: string; extension?: string }> {
  const original = () => ({ body: file.stream(), contentType: file.type || 'application/octet-stream' });
  // Required compatibility for deployed apps and independent AKH consumers.
  if (!policy.profile && (file.size <= policy.maxBytes || !env.IMAGES)) return original();
  if (!env.IMAGES) throw new ImageProcessingError(503, 'IMAGE_PROCESSOR_UNAVAILABLE', 'Image processing unavailable', true);
  try {
    const info = await env.IMAGES.info(file.stream());
    if (!('width' in info) || !['image/jpeg', 'image/png', 'image/gif', 'image/webp'].includes(info.format)) {
      throw new ImageProcessingError(400, 'UNSUPPORTED_IMAGE', 'Unsupported image format');
    }
    if (info.width <= 0 || info.height <= 0 || info.width * info.height > MAX_IMAGE_PIXELS) {
      throw new ImageProcessingError(413, 'IMAGE_TOO_LARGE', 'Image exceeds 40 MP');
    }
    const printArtwork = policy.profile === 'ticket-background';
    const format = printArtwork && ['image/gif', 'image/webp'].includes(info.format) ? 'image/png' : info.format;
    const outputBudget = policy.profile ? policy.maxBytes : MAX_IMAGE_INPUT_BYTES;
    let edge = policy.maxEdge;
    for (let attempt = 0; attempt < 6; attempt++) {
      const output = await env.IMAGES.input(file.stream())
        .transform({ width: edge, height: edge, fit: 'scale-down' })
        .output({ format, ...(format === 'image/png' || format === 'image/gif' ? {} : { quality: policy.quality }), anim: !printArtwork && (format === 'image/gif' || format === 'image/webp') });
      const response = output.response();
      const bytes = await response.arrayBuffer();
      if (bytes.byteLength <= outputBudget) {
        return { body: bytes, contentType: format, extension: format.split('/')[1].replace('jpeg', 'jpg') };
      }
      const next = Math.max(1, Math.floor(edge * Math.sqrt(outputBudget / bytes.byteLength) * .9));
      if (next >= edge) break;
      edge = next;
    }
    throw new ImageProcessingError(422, 'IMAGE_OUTPUT_TOO_LARGE', 'Image cannot fit the output budget');
  } catch (error) {
    if (!policy.profile) return original();
    if (error instanceof ImageProcessingError) throw error;
    console.error('Image transform failed', error instanceof Error ? error.message : String(error));
    throw new ImageProcessingError(502, 'IMAGE_TRANSFORM_FAILED', 'Image processing failed', true);
  }
}

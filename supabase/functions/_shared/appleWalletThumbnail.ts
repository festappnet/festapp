import { Buffer } from 'node:buffer';
import jpeg from 'npm:jpeg-js@0.4.4';
import { PNG } from 'npm:pngjs@5.0.0';
const thumbnails = new Map<string, Buffer>();

export function appleWalletPublicThumbnail(bytes: Buffer): Buffer | undefined {
  if (bytes.length < 24 || bytes.toString('ascii', 12, 16) !== 'IHDR') return;
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (width === 0 || height === 0 || width * height > 4_000_000) return;
  return squareThumbnail(PNG.sync.read(bytes));
}

/** Render the same immutable artwork used by the PDF into the Wallet thumbnail size. */
export async function appleWalletGalleryThumbnail(url: string): Promise<Buffer | undefined> {
  const cached = thumbnails.get(url);
  if (cached) return cached;
  const { galleryBackground } = await import('./ticketGallery.ts');
  const bytes = await galleryBackground(url);
  if (!bytes) return;
  const source = url.endsWith('.jpg')
    ? jpeg.decode(bytes)
    : PNG.sync.read(Buffer.from(bytes));
  const result = squareThumbnail(source);
  if (thumbnails.size >= 8) thumbnails.delete(thumbnails.keys().next().value!);
  thumbnails.set(url, result);
  return result;
}

function squareThumbnail(source: { width: number; height: number; data: Uint8Array }): Buffer {
  const cropSize = Math.min(source.width, source.height);
  const size = Math.min(cropSize, 270);
  const left = Math.floor((source.width - cropSize) / 2);
  const top = Math.floor((source.height - cropSize) / 2);
  const thumbnail = new PNG({ width: size, height: size });
  for (let y = 0; y < size; y++) {
    const sourceY = top + Math.floor((y + 0.5) * cropSize / size);
    for (let x = 0; x < size; x++) {
      const sourceX = left + Math.floor((x + 0.5) * cropSize / size);
      const offset = 4 * (sourceY * source.width + sourceX);
      const targetOffset = 4 * (y * size + x);
      thumbnail.data.set(source.data.subarray(offset, offset + 4), targetOffset);
    }
  }
  return PNG.sync.write(thumbnail);
}

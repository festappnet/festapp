import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { IMAGE_TRANSFORM_CONTRACT } from '../../src/transform-contract';

describe('checked-in topology', () => {
  const wrangler = readFileSync(resolve(__dirname, '../../wrangler.toml'), 'utf8');
  it('keeps explicit control and temporary pre-P3 public routes only', () => {
    expect(wrangler).toContain('image-api.festapp.net');
    expect(wrangler).toContain('img.festapp.net');
    expect(wrangler).toContain('a.img.festapp.net');
    expect(wrangler).toContain('akh.img.festapp.net');
    expect(wrangler).toContain('workers_dev = false');
  });
  it('has explicit public/private bindings and no phantom drift', () => {
    for (const name of ['festapp-images', 'festapp-images-a', 'festapp-images-akhweb', 'festapp-images-private', 'festapp-images-a-private']) {
      expect(wrangler).toContain(`bucket_name = "${name}"`);
    }
    expect(wrangler).not.toMatch(/IMAGES_TEMP|IMAGES_BUCKET_B|IMAGES_BUCKET_C/);
    expect(IMAGE_TRANSFORM_CONTRACT.publicHosts).toEqual(['img.festapp.net', 'a.img.festapp.net']);
  });
});

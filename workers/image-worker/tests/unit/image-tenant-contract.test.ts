import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { handleCors } from '../../src/cors';
import { projectRegistry } from '../../src/project-registry';
import type { Env } from '../../src/types';

const root = new URL('../../../../', import.meta.url);
const read = (path: string) => readFileSync(new URL(path, root), 'utf8');
const origins: string[] = JSON.parse(read('automation/cloudflare/festapp-public-cors.json'))
  .rules.flatMap((rule: { allowed: { origins: string[] } }) => rule.allowed.origins);
const tenants: string[] = JSON.parse(read('automation/tenant-overlays/tenant-overlay.schema.json'))
  .properties.tenantId.enum;
const configured = {
  CONTROL_ALLOWED_ORIGINS: read('workers/image-worker/wrangler.toml')
    .match(/^CONTROL_ALLOWED_ORIGINS = "([^"]+)"/m)![1],
} as Env;

describe('all active image clients', () => {
  it.each(origins)('accepts an upload preflight from %s', (origin) => {
    const response = handleCors(new Request('https://image-api.festapp.net/upload', {
      method: 'OPTIONS',
      headers: { Origin: origin },
    }), configured);
    expect(response.status).toBe(204);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe(origin);
    expect(response.headers.get('Access-Control-Allow-Methods')).toContain('POST');
    expect(response.headers.get('Access-Control-Allow-Headers')).toContain('Authorization');
  });

  it.each(tenants)('registers the image project selected by %s', (tenant) => {
    const source = read(`automation/tests/fixtures/tenants/${tenant}.conf`);
    const project = source.match(/^IMAGE_PROJECT_ID=(.+)$/m)?.[1].trim();
    expect(project).toBeTruthy();
    expect(projectRegistry({} as Env).map((entry) => entry.id)).toContain(project);
  });

  it.each(origins)('rejects an impersonation of %s', (origin) => {
    const response = handleCors(new Request('https://image-api.festapp.net/upload', {
      method: 'OPTIONS', headers: { Origin: `${origin}.evil.example` },
    }), configured);
    expect(response.status).toBe(403);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });
});

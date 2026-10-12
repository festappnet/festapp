import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { handleCors } from '../../src/cors';
import type { Env } from '../../src/types';

const config = readFileSync(new URL('../../wrangler.toml', import.meta.url), 'utf8');
const env = {
  CONTROL_ALLOWED_ORIGINS: config.match(/^CONTROL_ALLOWED_ORIGINS = "([^"]+)"/m)![1],
} as Env;

describe('Slunovrat image control origins', () => {
  it.each(['https://slunovrat.festapp.net', 'https://app.festivalslunovrat.cz'])(
    'allows an upload preflight from %s',
    (origin) => {
      const response = handleCors(new Request('https://image-api.festapp.net/upload', {
        method: 'OPTIONS',
        headers: {
          Origin: origin,
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Headers': 'authorization,content-type',
        },
      }), env);
      expect(response.status).toBe(204);
      expect(response.headers.get('Access-Control-Allow-Origin')).toBe(origin);
      expect(response.headers.get('Access-Control-Allow-Headers')).toBe('Authorization, Content-Type');
      expect(response.headers.get('Vary')).toBe('Origin');
    },
  );

  it('rejects a domain impersonating Slunovrat', () => {
    const response = handleCors(new Request('https://image-api.festapp.net/upload', {
      method: 'OPTIONS',
      headers: { Origin: 'https://slunovrat.festapp.net.evil.example' },
    }), env);
    expect(response.status).toBe(403);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });
});

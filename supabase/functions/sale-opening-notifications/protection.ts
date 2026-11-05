import { emailPayloadHash } from '../_shared/emailPayload.ts';

const action = 'sale_opening_subscribe';
export type ProtectionConfig = { siteKey: string; secret: string; hostnames: string[] };
export function protectionConfig(env = (key: string) => Deno.env.get(key)): ProtectionConfig {
  const config = {
    siteKey: env('SALE_OPENING_TURNSTILE_SITE_KEY') ?? '',
    secret: env('SALE_OPENING_TURNSTILE_SECRET_KEY') ?? '',
    hostnames: (env('SALE_OPENING_TURNSTILE_HOSTNAMES') ?? '').split(',').map(s => s.trim()).filter(Boolean),
  };
  // Never silently disable bot verification when deployment configuration is missing.
  if (!config.siteKey || !config.secret || !config.hostnames.length) throw new Error('protection_unavailable');
  const testKey = /^[123]x0+/.test(config.siteKey) || /^[123]x0+/.test(config.secret);
  if (testKey && (!['localhost', '127.0.0.1', '[::1]'].includes(new URL(env('SUPABASE_URL') ?? '').hostname) ||
    config.hostnames.some(h => !['localhost', '127.0.0.1', '[::1]'].includes(h)))) throw new Error('protection_test_key_forbidden');
  return config;
}
export const protectionBinding = (formLink: string, email: string) => emailPayloadHash(JSON.stringify([formLink, email.trim().toLowerCase()]));
export function saleOpeningProtection(config = protectionConfig, fetcher: typeof fetch = fetch) {
  return {
    publicConfig: () => ({ siteKey: config().siteKey, action }),
    async verify(token: unknown, formLink: string, email: string): Promise<boolean> {
      if (typeof token !== 'string' || token.length < 1 || token.length > 2048) return false;
      const settings = config();
      // No untrusted X-Forwarded-For/CF-Connecting-IP supplied by the caller.
      const result = await fetcher('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(8000),
        body: new URLSearchParams({secret: settings.secret, response: token}),
      });
      if (!result.ok) throw new Error('protection_unavailable');
      const proof = await result.json();
      return proof.success === true && settings.hostnames.includes(proof.hostname) &&
        proof.action === action && proof.cdata === await protectionBinding(formLink, email);
    },
  };
}

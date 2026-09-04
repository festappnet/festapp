import assert from 'node:assert/strict';
import test from 'node:test';
import {
  configFromEnvironment,
  ensurePagesProject,
} from '../cloudflare/ensure-pages-project.mjs';

const config = {
  token: 'token', accountId: 'account', project: 'hvezdamorska',
  branch: 'prod/hvezdamorska', domain: 'hvezdamorska.festapp.net',
  zone: 'festapp.net',
  phase: 'legacy', runtimeSupabaseUrl: 'https://legacy.supabase.co',
  runtimeSupabaseAnonKey: 'public-anon', runtimeOrganizationId: '4',
  manageDns: true,
};

function response(status, result, success = status >= 200 && status < 300) {
  return { status, ok: success, json: async () => ({ success, result, errors: [] }) };
}

test('creates a missing project, configures public worker env, and adds domain', async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options, body: options.body ? JSON.parse(options.body) : undefined });
    if (calls.length === 1) return response(404, null, false);
    if (calls.length === 2) return response(200, { name: config.project });
    if (calls.length === 3) return response(200, {
      name: config.project, production_branch: config.branch,
    });
    if (calls.length === 4) return response(404, null, false);
    if (calls.length === 5) return response(200, { name: config.domain, status: 'initializing' });
    if (calls.length === 6) return response(200, [{ id: 'zone-id', name: config.zone }]);
    if (calls.length === 7) return response(200, []);
    return response(200, { id: 'dns-id' });
  };

  const result = await ensurePagesProject(config, fetchImpl);
  assert.equal(result.created, true);
  assert.equal(result.domainAdded, true);
  assert.equal(result.dnsAdded, true);
  assert.equal(result.dnsStatus, 'created');
  assert.equal(calls[1].options.method, 'POST');
  assert.deepEqual(calls[1].body, { name: config.project, production_branch: config.branch });
  assert.equal(calls[2].body.deployment_configs.production.env_vars.SUPABASE_URL.value,
    config.runtimeSupabaseUrl);
  assert.equal(calls[2].body.deployment_configs.production.env_vars.ORGANIZATION_ID.value, '4');
  assert.equal(calls[4].body.name, config.domain);
  assert.equal(new URL(calls[5].url).searchParams.get('name'), config.zone);
  assert.equal(new URL(calls[5].url).searchParams.has('account.id'), false,
    'DNS zone ownership must not be coupled to the Pages account');
  assert.deepEqual(calls[7].body, {
    type: 'CNAME', name: config.domain, content: 'hvezdamorska.pages.dev',
    proxied: true, ttl: 1,
    comment: 'Managed by Festapp Cloudflare Pages deployment automation',
  });
});

test('updates only owned environment-variable keys on an existing project', async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options, body: options.body ? JSON.parse(options.body) : undefined });
    if (calls.length === 1) return response(200, {
      name: config.project,
      deployment_configs: { production: { env_vars: {
        KEEP_ME: { type: 'plain_text', value: 'yes' },
      } } },
    });
    if (calls.length === 2) return response(200, {
      name: config.project, production_branch: config.branch,
    });
    return response(200, { name: config.domain, status: 'active' });
  };

  const result = await ensurePagesProject(config, fetchImpl);
  assert.equal(result.created, false);
  assert.equal(result.domainAdded, false);
  assert.equal(result.dnsAdded, false);
  assert.equal(result.dnsStatus, 'active-custom-domain');
  assert.equal(calls.length, 3);
  assert.deepEqual(Object.keys(calls[1].body.deployment_configs.production.env_vars).sort(),
    ['ORGANIZATION_ID', 'SUPABASE_ANON_KEY', 'SUPABASE_URL']);
});

test('refuses to replace a conflicting custom-domain DNS record', async () => {
  let call = 0;
  const fetchImpl = async () => {
    call += 1;
    if (call === 1) return response(200, { name: config.project });
    if (call === 2) return response(200, {
      name: config.project, production_branch: config.branch,
    });
    if (call === 3) return response(200, { name: config.domain, status: 'initializing' });
    if (call === 4) return response(200, [{ id: 'zone-id', name: config.zone }]);
    return response(200, [{
      type: 'A', name: config.domain, content: '192.0.2.10', proxied: true,
    }]);
  };

  await assert.rejects(ensurePagesProject(config, fetchImpl), /refusing to overwrite conflicting DNS/);
});

test('replaces only an explicitly approved legacy DNS record', async () => {
  const takeover = {
    ...config,
    domain: 'app.absolventskyvelehrad.cz',
    zone: 'absolventskyvelehrad.cz',
    project: 'absolventskyvelehrad',
    branch: 'prod/absolventskyvelehrad',
    legacyDnsRecord: { type: 'A', content: '75.2.60.5' },
  };
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options, body: options.body ? JSON.parse(options.body) : undefined });
    if (calls.length === 1) return response(200, { name: takeover.project });
    if (calls.length === 2) return response(200, {
      name: takeover.project, production_branch: takeover.branch,
    });
    if (calls.length === 3) return response(200, {
      name: takeover.domain, status: 'initializing',
    });
    if (calls.length === 4) return response(200, [{ id: 'zone-id', name: takeover.zone }]);
    if (calls.length === 5) return response(200, [{
      id: 'legacy-record-id', type: 'A', name: takeover.domain,
      content: '75.2.60.5', proxied: false,
    }]);
    return response(200, { id: 'legacy-record-id' });
  };

  const result = await ensurePagesProject(takeover, fetchImpl);
  assert.equal(result.dnsAdded, false);
  assert.equal(result.dnsReplaced, true);
  assert.equal(result.dnsStatus, 'replaced-approved-legacy');
  assert.match(calls[5].url, /dns_records\/legacy-record-id$/);
  assert.equal(calls[5].options.method, 'PUT');
  assert.deepEqual(calls[5].body, {
    type: 'CNAME', name: takeover.domain, content: 'absolventskyvelehrad.pages.dev',
    proxied: true, ttl: 1,
    comment: 'Managed by Festapp Cloudflare Pages deployment automation',
  });
});

test('prepares an apex custom domain without mutating externally managed DNS', async () => {
  const external = { ...config, domain: 'vstupenky.online', zone: 'vstupenky.online', manageDns: false };
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });
    if (calls.length === 1) return response(404, null, false);
    if (calls.length === 2) return response(200, { name: external.project });
    if (calls.length === 3) return response(200, { name: external.project, production_branch: external.branch });
    if (calls.length === 4) return response(404, null, false);
    return response(200, { name: external.domain, status: 'initializing' });
  };
  const result = await ensurePagesProject(external, fetchImpl);
  assert.equal(result.domainStatus, 'initializing');
  assert.equal(result.dnsStatus, 'external-dns-required');
  assert.equal(result.dnsAdded, false);
  assert.equal(calls.length, 5, 'external DNS mode must not call Cloudflare Zone DNS APIs');
});

test('rejects unsafe deployment configuration before network access', () => {
  assert.throws(() => configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'bad/project',
    BRANCH: 'main', DOMAIN: 'https://bad.example', SUPABASE_URL: 'http://bad.example',
    SUPABASE_ANON_KEY: 'anon', ORGANIZATION_ID: '0', BACKEND_ACTIVATION_PHASE: 'legacy',
  }));
});

test('selects the complete canonical Worker profile only in canonical phase', () => {
  const resolved = configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'hvezdamorska',
    BRANCH: 'prod/hvezdamorska', DOMAIN: 'hvezdamorska.festapp.net',
    SUPABASE_URL: 'https://legacy.supabase.co', SUPABASE_ANON_KEY: 'legacy-anon',
    ORGANIZATION_ID: '4', BACKEND_ACTIVATION_PHASE: 'canonical',
    BACKEND_ACTIVATION_TENANT_ID: 'hvezdamorska',
    BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL: 'https://api.festapp.net',
    BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY: 'canonical-anon',
    BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID: '7',
  });
  assert.equal(resolved.runtimeSupabaseUrl, 'https://api.festapp.net');
  assert.equal(resolved.runtimeSupabaseAnonKey, 'canonical-anon');
  assert.equal(resolved.runtimeOrganizationId, '7');
  assert.equal(resolved.zone, 'festapp.net');
});

test('a fully disabled activation profile remains a backward-compatible legacy deploy', () => {
  const resolved = configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'festapp-web',
    BRANCH: 'prod/festapp-web', DOMAIN: 'web.festapp.net',
    SUPABASE_URL: 'https://legacy.supabase.co', SUPABASE_ANON_KEY: 'legacy-anon',
    ORGANIZATION_ID: '2',
  });
  assert.equal(resolved.phase, 'legacy');
  assert.equal(resolved.runtimeSupabaseUrl, 'https://legacy.supabase.co');
});

test('accepts an externally managed apex domain only when explicitly configured', () => {
  const resolved = configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'vstupenkyonline',
    BRANCH: 'prod/festapptickets', DOMAIN: 'vstupenky.online',
    CLOUDFLARE_MANAGE_DNS: 'false',
    SUPABASE_URL: 'https://legacy.supabase.co', SUPABASE_ANON_KEY: 'legacy-anon',
    ORGANIZATION_ID: '3',
  });
  assert.equal(resolved.zone, 'vstupenky.online');
  assert.equal(resolved.manageDns, false);
});

test('parses a complete approved legacy DNS takeover contract', () => {
  const resolved = configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'absolventskyvelehrad',
    BRANCH: 'prod/absolventskyvelehrad', DOMAIN: 'app.absolventskyvelehrad.cz',
    CLOUDFLARE_LEGACY_DNS_TYPE: 'A', CLOUDFLARE_LEGACY_DNS_TARGET: '75.2.60.5',
    SUPABASE_URL: 'https://legacy.supabase.co', SUPABASE_ANON_KEY: 'legacy-anon',
    ORGANIZATION_ID: '5',
  });
  assert.deepEqual(resolved.legacyDnsRecord, { type: 'A', content: '75.2.60.5' });
});

test('rejects a partial legacy DNS takeover contract', () => {
  assert.throws(() => configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'absolventskyvelehrad',
    BRANCH: 'prod/absolventskyvelehrad', DOMAIN: 'app.absolventskyvelehrad.cz',
    CLOUDFLARE_LEGACY_DNS_TYPE: 'A',
    SUPABASE_URL: 'https://legacy.supabase.co', SUPABASE_ANON_KEY: 'legacy-anon',
    ORGANIZATION_ID: '5',
  }), /legacy DNS takeover configuration must be complete/);
});

test('a partially populated activation profile fails closed', () => {
  assert.throws(() => configFromEnvironment({
    CF_API_TOKEN: 'x', CF_ACCOUNT_ID: 'a', CF_PROJECT: 'festapp-web',
    BRANCH: 'prod/festapp-web', DOMAIN: 'web.festapp.net',
    SUPABASE_URL: 'https://legacy.supabase.co', SUPABASE_ANON_KEY: 'legacy-anon',
    ORGANIZATION_ID: '2', BACKEND_ACTIVATION_PHASE: 'legacy',
  }), /fully populated or fully disabled/);
});

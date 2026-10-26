#!/usr/bin/env node

const API_ROOT = 'https://api.cloudflare.com/client/v4';

function required(name, value) {
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function assertSlug(name, value) {
  if (!/^[a-z0-9][a-z0-9-]{0,57}[a-z0-9]$/.test(value)) {
    throw new Error(`${name} is not a valid Cloudflare Pages project name`);
  }
  return value;
}

function assertBranch(value) {
  if (!/^prod\/[a-z0-9][a-z0-9-]*$/.test(value)) {
    throw new Error('BRANCH must be a prod/* branch');
  }
  return value;
}

function assertDomain(value) {
  if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$/.test(value)) {
    throw new Error('DOMAIN must be a DNS hostname');
  }
  return value;
}

function legacyDnsRecordFromEnvironment(env) {
  const typeValue = (env.CLOUDFLARE_LEGACY_DNS_TYPE || '').trim().toUpperCase();
  const content = (env.CLOUDFLARE_LEGACY_DNS_TARGET || '').trim();
  if (!typeValue && !content) return null;
  if (!typeValue || !content) {
    throw new Error('legacy DNS takeover configuration must be complete');
  }
  if (!['A', 'AAAA', 'CNAME'].includes(typeValue)) {
    throw new Error('CLOUDFLARE_LEGACY_DNS_TYPE must be A, AAAA, or CNAME');
  }
  if (content.length > 253 || /\s/.test(content)) {
    throw new Error('CLOUDFLARE_LEGACY_DNS_TARGET is invalid');
  }
  return { type: typeValue, content };
}

async function api(fetchImpl, token, accountId, path, options = {}) {
  const response = await fetchImpl(`${API_ROOT}/accounts/${accountId}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  const body = await response.json().catch(() => ({}));
  return { response, body };
}

async function zoneApi(fetchImpl, token, path, options = {}) {
  const response = await fetchImpl(`${API_ROOT}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  const body = await response.json().catch(() => ({}));
  return { response, body };
}

function publicRuntimeEnv(config) {
  return {
    SUPABASE_URL: { type: 'plain_text', value: config.runtimeSupabaseUrl },
    SUPABASE_ANON_KEY: { type: 'plain_text', value: config.runtimeSupabaseAnonKey },
    ORGANIZATION_ID: { type: 'plain_text', value: config.runtimeOrganizationId },
  };
}

function requireSuccess(label, call) {
  if (!call.response.ok || call.body.success !== true) {
    const details = (call.body.errors || []).map((error) => error.message).filter(Boolean).join('; ');
    throw new Error(`${label} failed (${call.response.status})${details ? `: ${details}` : ''}`);
  }
  return call.body.result;
}

export async function ensurePagesProject(config, fetchImpl = fetch) {
  const projectPath = `/pages/projects/${encodeURIComponent(config.project)}`;
  const current = await api(fetchImpl, config.token, config.accountId, projectPath);
  let project;
  let created = false;

  if (current.response.status === 404) {
    project = requireSuccess('Cloudflare Pages project creation', await api(
      fetchImpl,
      config.token,
      config.accountId,
      '/pages/projects',
      {
        method: 'POST',
        body: JSON.stringify({ name: config.project, production_branch: config.branch }),
      },
    ));
    created = true;
  } else {
    project = requireSuccess('Cloudflare Pages project lookup', current);
  }

  // Cloudflare PATCH treats env-var keys as individual mutations; omitted keys
  // are retained and only an explicit null deletes one. Sending back masked
  // secret values from the GET response could otherwise corrupt unrelated
  // bindings, so update only the three public values owned by this bundle.
  const envVars = publicRuntimeEnv(config);
  project = requireSuccess('Cloudflare Pages project configuration', await api(
    fetchImpl,
    config.token,
    config.accountId,
    projectPath,
    {
      method: 'PATCH',
      body: JSON.stringify({
        production_branch: config.branch,
        deployment_configs: { production: { env_vars: envVars } },
      }),
    },
  ));

  const domainPath = `${projectPath}/domains/${encodeURIComponent(config.domain)}`;
  const domainLookup = await api(fetchImpl, config.token, config.accountId, domainPath);
  let domain;
  let domainAdded = false;
  if (domainLookup.response.status === 404) {
    domain = requireSuccess('Cloudflare Pages custom-domain creation', await api(
      fetchImpl,
      config.token,
      config.accountId,
      `${projectPath}/domains`,
      { method: 'POST', body: JSON.stringify({ name: config.domain }) },
    ));
    domainAdded = true;
  } else {
    domain = requireSuccess('Cloudflare Pages custom-domain lookup', domainLookup);
  }

  const expectedDnsTarget = `${config.project}.pages.dev`;
  let dnsAdded = false;
  let dnsReplaced = false;
  let dnsStatus = 'active-custom-domain';
  // Once Pages reports the custom domain active, Cloudflare has already
  // validated its routing. Avoid requiring Zone DNS permissions on every
  // subsequent deploy; the narrower Pages token is sufficient from then on.
  // Initializing/new domains still require an exact, fail-closed DNS check.
  const inspectDns = domain.status !== 'active' || Boolean(config.legacyDnsRecord);
  if (inspectDns && config.manageDns === false) {
    dnsStatus = 'external-dns-required';
  } else if (inspectDns) {
    const zoneLookup = requireSuccess('Cloudflare zone lookup', await zoneApi(
      fetchImpl,
      config.token,
      `/zones?name=${encodeURIComponent(config.zone)}`,
    ));
    if (!Array.isArray(zoneLookup) || zoneLookup.length !== 1 || zoneLookup[0].name !== config.zone) {
      throw new Error(`Cloudflare zone lookup returned no unique ${config.zone} zone`);
    }
    const zoneId = zoneLookup[0].id;
    const dnsLookup = requireSuccess('Cloudflare Pages DNS lookup', await zoneApi(
      fetchImpl,
      config.token,
      `/zones/${encodeURIComponent(zoneId)}/dns_records?name=${encodeURIComponent(config.domain)}`,
    ));
    if (dnsLookup.length === 0) {
      requireSuccess('Cloudflare Pages DNS creation', await zoneApi(
        fetchImpl,
        config.token,
        `/zones/${encodeURIComponent(zoneId)}/dns_records`,
        {
          method: 'POST',
          body: JSON.stringify({
            type: 'CNAME',
            name: config.domain,
            content: expectedDnsTarget,
            proxied: true,
            ttl: 1,
            comment: 'Managed by Festapp Cloudflare Pages deployment automation',
          }),
        },
      ));
      dnsAdded = true;
      dnsStatus = 'created';
    } else if (dnsLookup.length === 1 && dnsLookup[0].type === 'CNAME' &&
        dnsLookup[0].content === expectedDnsTarget && dnsLookup[0].proxied === true) {
      dnsStatus = 'verified';
    } else if (dnsLookup.length === 1 && config.legacyDnsRecord && dnsLookup[0].id &&
        dnsLookup[0].type === config.legacyDnsRecord.type &&
        dnsLookup[0].content === config.legacyDnsRecord.content) {
      requireSuccess('Cloudflare approved legacy DNS replacement', await zoneApi(
        fetchImpl,
        config.token,
        `/zones/${encodeURIComponent(zoneId)}/dns_records/${encodeURIComponent(dnsLookup[0].id)}`,
        {
          method: 'PUT',
          body: JSON.stringify({
            type: 'CNAME',
            name: config.domain,
            content: expectedDnsTarget,
            proxied: true,
            ttl: 1,
            comment: 'Managed by Festapp Cloudflare Pages deployment automation',
          }),
        },
      ));
      dnsReplaced = true;
      dnsStatus = 'replaced-approved-legacy';
    } else {
      throw new Error(`refusing to overwrite conflicting DNS for ${config.domain}`);
    }
  }

  return {
    project: project.name || config.project,
    productionBranch: project.production_branch || config.branch,
    created,
    domain: domain.name || config.domain,
    domainStatus: domain.status || 'initializing',
    domainAdded,
    dnsTarget: expectedDnsTarget,
    dnsAdded,
    dnsReplaced,
    dnsStatus,
  };
}

export function configFromEnvironment(env = process.env) {
  const activationFields = [
    'BACKEND_ACTIVATION_TENANT_ID',
    'BACKEND_ACTIVATION_PHASE',
    'BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL',
    'BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY',
    'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID',
  ];
  const populatedActivationFields = activationFields.filter((name) => Boolean(env[name]));
  let phase = env.BACKEND_ACTIVATION_PHASE || '';
  if (!phase && populatedActivationFields.length === 0) {
    phase = 'legacy';
  } else if (!phase || populatedActivationFields.length !== activationFields.length) {
    throw new Error('backend activation profile must be fully populated or fully disabled');
  }
  if (!['legacy', 'canonical'].includes(phase)) {
    throw new Error('BACKEND_ACTIVATION_PHASE must be legacy or canonical');
  }
  const urlName = phase === 'canonical'
    ? 'BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL' : 'SUPABASE_URL';
  const keyName = phase === 'canonical'
    ? 'BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY' : 'SUPABASE_ANON_KEY';
  const organizationName = phase === 'canonical'
    ? 'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID' : 'ORGANIZATION_ID';
  const supabaseUrl = new URL(required(urlName, env[urlName]));
  if (supabaseUrl.protocol !== 'https:' || supabaseUrl.pathname !== '/') {
    throw new Error(`${urlName} must be an HTTPS origin`);
  }
  const organizationId = required(organizationName, env[organizationName]);
  if (!/^[1-9][0-9]*$/.test(organizationId)) throw new Error('ORGANIZATION_ID must be positive');
  const labels = assertDomain(required('DOMAIN', env.DOMAIN)).split('.');
  if (labels.length < 2) throw new Error('DOMAIN must be a DNS hostname');
  const domain = labels.join('.');
  return {
    token: required('CF_API_TOKEN', env.CF_API_TOKEN),
    accountId: required('CF_ACCOUNT_ID', env.CF_ACCOUNT_ID),
    project: assertSlug('CF_PROJECT', required('CF_PROJECT', env.CF_PROJECT)),
    branch: assertBranch(required('BRANCH', env.BRANCH)),
    domain,
    zone: labels.slice(-2).join('.'),
    manageDns: env.CLOUDFLARE_MANAGE_DNS !== 'false',
    legacyDnsRecord: legacyDnsRecordFromEnvironment(env),
    phase,
    runtimeSupabaseUrl: supabaseUrl.origin,
    runtimeSupabaseAnonKey: required(keyName, env[keyName]),
    runtimeOrganizationId: organizationId,
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  ensurePagesProject(configFromEnvironment())
    .then((result) => console.log(JSON.stringify(result)))
    .catch((error) => {
      console.error(`ERROR: ${error.message}`);
      process.exitCode = 1;
    });
}

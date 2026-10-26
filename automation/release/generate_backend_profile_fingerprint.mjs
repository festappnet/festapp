#!/usr/bin/env node

import { canonicalBackendProfileSha256 } from '../lib/backend_activation_manifest.mjs';
import { parseSupabaseOrigin } from '../lib/supabase_client_config.mjs';

const [tenantId, originValue, canonicalAnonKey, organizationValue] = process.argv.slice(2);
const canonicalOrganizationId = Number(organizationValue);
if (!tenantId || !originValue || !canonicalAnonKey || !organizationValue) {
  throw new Error(
    'usage: generate_backend_profile_fingerprint.mjs TENANT ORIGIN ANON_KEY ORGANIZATION_ID',
  );
}

process.stdout.write(canonicalBackendProfileSha256({
  tenantId,
  canonicalOrigin: parseSupabaseOrigin(originValue),
  canonicalAnonKey,
  canonicalOrganizationId,
}));

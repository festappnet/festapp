import crypto from 'node:crypto';

export const backendActivationSchemaVersion = 1;
export const canonicalBackendGeneration = 1;

export function backendActivationDocument(tenantId, backend) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(tenantId)) {
    throw new Error('backend activation tenant ID must be a lowercase slug');
  }
  if (!['legacy', 'canonical'].includes(backend)) {
    throw new Error('backend activation phase must be legacy or canonical');
  }
  return `${JSON.stringify({
    schemaVersion: backendActivationSchemaVersion,
    tenantId,
    generation: backend === 'canonical' ? canonicalBackendGeneration : 0,
    backend,
  })}\n`;
}

export function canonicalBackendActivationSha256(tenantId) {
  return crypto.createHash('sha256')
    .update(backendActivationDocument(tenantId, 'canonical'))
    .digest('hex');
}

export function canonicalBackendProfileSha256({
  tenantId,
  canonicalOrigin,
  canonicalAnonKey,
  canonicalOrganizationId,
}) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(tenantId)) {
    throw new Error('backend activation tenant ID must be a lowercase slug');
  }
  if (!Number.isSafeInteger(canonicalOrganizationId) || canonicalOrganizationId <= 0) {
    throw new Error('canonical organization ID must be a positive integer');
  }
  const anonKeySha256 = crypto.createHash('sha256').update(canonicalAnonKey).digest('hex');
  const profile = JSON.stringify({
    schemaVersion: backendActivationSchemaVersion,
    tenantId,
    generation: canonicalBackendGeneration,
    canonicalOrigin,
    anonKeySha256,
    canonicalOrganizationId,
  });
  return crypto.createHash('sha256').update(profile).digest('hex');
}

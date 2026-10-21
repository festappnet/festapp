import crypto from 'node:crypto';

export function evidenceHash(value, key) {
  if (value === null || value === undefined || value === '') return null;
  return crypto.createHmac('sha256', key).update(String(value)).digest('hex');
}

export function classifyAuthCollisions(defaultUsers, aUsers, key) {
  const defaultById = new Map(defaultUsers.map((user) => [user.id, user]));
  const defaultByEmail = new Map(defaultUsers.filter((user) => user.normalized_email)
    .map((user) => [user.normalized_email, user]));
  const sameUuidDifferentEmail = [];
  const sameEmailDifferentUuid = [];
  const sameIdentity = [];
  const sameProviderIdentityDifferentUuid = [];
  const sameVerifiedPhoneDifferentUuid = [];
  for (const user of aUsers) {
    const byId = defaultById.get(user.id);
    if (byId) {
      const entry = {
        default_user_id: byId.id,
        a_user_id: user.id,
        default_email_hmac: evidenceHash(byId.normalized_email, key),
        a_email_hmac: evidenceHash(user.normalized_email, key),
        default_verified: Boolean(byId.verified),
        a_verified: Boolean(user.verified),
        default_auth_state: safeAuthState(byId, key),
        a_auth_state: safeAuthState(user, key),
      };
      if (byId.normalized_email !== user.normalized_email) sameUuidDifferentEmail.push(entry);
      else sameIdentity.push(entry);
    }
    const byEmail = user.normalized_email && defaultByEmail.get(user.normalized_email);
    if (byEmail && byEmail.id !== user.id) {
      sameEmailDifferentUuid.push({
        default_user_id: byEmail.id,
        a_user_id: user.id,
        email_hmac: evidenceHash(user.normalized_email, key),
        default_verified: Boolean(byEmail.verified),
        a_verified: Boolean(user.verified),
        default_auth_state: safeAuthState(byEmail, key),
        a_auth_state: safeAuthState(user, key),
        status: byEmail.verified && user.verified ? 'manual-merge-required' : 'ambiguous-unverified-blocker',
      });
    }
  }
  const defaultProviderLinks = new Map();
  for (const user of defaultUsers) for (const link of user.provider_links ?? []) {
    defaultProviderLinks.set(`${link.provider}\0${link.provider_id}`, user);
  }
  for (const user of aUsers) for (const link of user.provider_links ?? []) {
    const canonical = defaultProviderLinks.get(`${link.provider}\0${link.provider_id}`);
    if (canonical && canonical.id !== user.id) {
      sameProviderIdentityDifferentUuid.push({
        provider: link.provider,
        provider_id_hmac: evidenceHash(link.provider_id, key),
        default_user_id: canonical.id,
        a_user_id: user.id,
        status: 'manual-provider-collision-blocker',
      });
    }
  }
  const defaultPhones = new Map(defaultUsers.filter((user) => user.normalized_phone && user.phone_verified)
    .map((user) => [user.normalized_phone, user]));
  for (const user of aUsers.filter((value) => value.normalized_phone && value.phone_verified)) {
    const canonical = defaultPhones.get(user.normalized_phone);
    if (canonical && canonical.id !== user.id) {
      sameVerifiedPhoneDifferentUuid.push({
        phone_hmac: evidenceHash(user.normalized_phone, key),
        default_user_id: canonical.id,
        a_user_id: user.id,
        status: 'manual-phone-collision-blocker',
      });
    }
  }
  return {
    same_uuid_different_email: sameUuidDifferentEmail,
    same_email_different_uuid: sameEmailDifferentUuid,
    same_provider_identity_different_uuid: sameProviderIdentityDifferentUuid,
    same_verified_phone_different_uuid: sameVerifiedPhoneDifferentUuid,
    same_identity: sameIdentity,
  };
}

function safeAuthState(user, key) {
  return {
    providers: user.providers ?? [],
    provider_links: (user.provider_links ?? []).map(({ provider, provider_id }) => ({
      provider,
      provider_id_hmac: evidenceHash(provider_id, key),
    })),
    mfa: user.mfa ?? [],
    phone_hmac: evidenceHash(user.normalized_phone, key),
    phone_verified: Boolean(user.phone_verified),
    is_sso_user: Boolean(user.is_sso_user),
    is_anonymous: Boolean(user.is_anonymous),
    pending_tokens: {
      confirmation: Boolean(user.confirmation_pending),
      recovery: Boolean(user.recovery_pending),
      email_change: Boolean(user.email_change_pending),
      phone_change: Boolean(user.phone_change_pending),
      reauthentication: Boolean(user.reauthentication_pending),
    },
  };
}

export function classifyStorageCollisions(defaultObjects, aObjects, key) {
  const defaultByKey = new Map(defaultObjects.map((object) => [`${object.bucket_id}\0${object.name}`, object]));
  const collisions = [];
  for (const object of aObjects) {
    const canonical = defaultByKey.get(`${object.bucket_id}\0${object.name}`);
    if (!canonical) continue;
    const etagKnown = Boolean(canonical.etag && object.etag);
    const sameMetadata = etagKnown && canonical.etag === object.etag && String(canonical.size) === String(object.size);
    collisions.push({
      bucket_id: object.bucket_id,
      object_key_hmac: evidenceHash(object.name, key),
      default_size: canonical.size === null ? null : Number(canonical.size),
      a_size: object.size === null ? null : Number(object.size),
      metadata_match: sameMetadata,
      status: sameMetadata ? 'requires-object-sha256-confirmation' : 'content-collision-blocker',
    });
  }
  return collisions;
}

import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL || 'http://127.0.0.1:54321';
const anonKey = process.env.SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (process.env.CONFIRM_DISPOSABLE_ACCOUNT_DELETION_TEST !== 'local-only') {
  throw new Error('Set CONFIRM_DISPOSABLE_ACCOUNT_DELETION_TEST=local-only');
}
if (!/^http:\/\/(127\.0\.0\.1|localhost):54321$/.test(url)) {
  throw new Error(`Refusing destructive disposable-user test outside local Supabase: ${url}`);
}
if (!anonKey || !serviceKey) throw new Error('Local SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are required');

const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
const suffix = crypto.randomUUID();
const email = `deletion-${suffix}@example.test`;
const password = `Disposable-${crypto.randomUUID()}!`;
let userId;
let occasionId;
let eventId;
let unitId;
let deletionRequestId;
let createdOrganization = false;
let createdUnit = false;
const createdTemplateIds = [];

async function nextId(table, floor = 1) {
  const { data, error } = await admin.from(table).select('id').order('id', { ascending: false }).limit(1);
  if (error) throw error;
  return Math.max(floor, Number(data?.[0]?.id || 0) + 1);
}

async function ignoreCleanupFailure(query) {
  try {
    await query;
  } catch {
    // Preserve the original test failure while best-effort cleanup continues.
  }
}

async function pollConfirmationLink() {
  const mailpit = 'http://127.0.0.1:54324/api/v1';
  for (let attempt = 0; attempt < 30; attempt++) {
    const list = await fetch(`${mailpit}/search?query=${encodeURIComponent(`to:${email}`)}`)
      .then((response) => response.ok ? response.json() : { messages: [] });
    const message = list?.messages?.[0];
    const id = message?.ID;
    if (id) {
      const detail = await fetch(`${mailpit}/message/${id}`).then((response) => response.json());
      const raw = JSON.stringify(detail);
      const match = raw.match(/https?:\\?\/\\?\/[^"'<>\\s]+\/delete-account\?token=[A-Za-z0-9_%-]+/);
      if (match) return match[0].replaceAll('\\/', '/');
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error('Confirmation email did not arrive in local Inbucket');
}

try {
  const { data: existingOrganization, error: organizationLookupError } = await admin
    .from('organizations').select('id').eq('id', 9).maybeSingle();
  if (organizationLookupError) throw organizationLookupError;
  if (!existingOrganization) {
    const { error } = await admin.from('organizations').insert({
      id: 9, title: 'Disposable CSM deletion fixture', data: {},
    });
    if (error) throw error;
    createdOrganization = true;
  }

  const { data: existingUnit, error: unitLookupError } = await admin
    .from('units').select('id').eq('organization', 9).limit(1).maybeSingle();
  if (unitLookupError) throw unitLookupError;
  if (existingUnit) {
    unitId = existingUnit.id;
  } else {
    unitId = await nextId('units', 900000);
    const { error } = await admin.from('units').insert({
      id: unitId, organization: 9, title: 'Disposable deletion unit',
    });
    if (error) throw error;
    createdUnit = true;
  }

  for (const template of [
    {
      code: 'ACCOUNT_DELETION_CONFIRM',
      title: 'Disposable deletion confirmation',
      subject: 'Confirm account deletion',
      html: '<a href="{{confirmationUrl}}">Confirm deletion</a>',
    },
    {
      code: 'ACCOUNT_DELETION_COMPLETE',
      title: 'Disposable deletion completed',
      subject: 'Account deleted',
      html: '<p>Your {{appName}} account was deleted.</p>',
    },
  ]) {
    const { data: existing, error: lookupError } = await admin.from('email_templates')
      .select('id').eq('organization', 9).eq('code', template.code).maybeSingle();
    if (lookupError) throw lookupError;
    if (!existing) {
      const id = await nextId('email_templates', 900000);
      const { error } = await admin.from('email_templates').insert({
        id, organization: 9, ...template,
      });
      if (error) throw error;
      createdTemplateIds.push(id);
    }
  }

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email, password, email_confirm: true,
  });
  if (createError) throw createError;
  userId = created.user.id;

  const { error: profileError } = await admin.from('user_info').upsert({
    id: userId, name: 'Disposable', surname: 'Deletion', email_readonly: email, organization: 9,
  });
  if (profileError) throw profileError;
  occasionId = await nextId('occasions', 900000);
  const { data: occasion, error: occasionError } = await admin.from('occasions').insert({
    id: occasionId, title: `Disposable deletion ${suffix}`, link: `delete-${suffix}`,
    organization: 9, start_time: new Date().toISOString(),
    end_time: new Date(Date.now() + 3600000).toISOString(), is_open: true, unit: unitId,
  }).select('id').single();
  if (occasionError) throw occasionError;
  occasionId = occasion.id;
  eventId = await nextId('events', 900000);
  const { data: event, error: eventError } = await admin.from('events').insert({
    id: eventId, occasion: occasionId, title: 'Seeded disposable registration',
    start_time: new Date().toISOString(), end_time: new Date(Date.now() + 1800000).toISOString(),
  }).select('id').single();
  if (eventError) throw eventError;
  for (const [table, row] of [
    ['organization_users', { user: userId, organization: 9 }],
    ['occasion_users', { user: userId, occasion: occasionId, is_approved: true }],
    ['event_users', { user: userId, event: event.id }],
    ['event_users_saved', { user: userId, event: event.id }],
    ['event_feedback', { user: userId, event: event.id, occasion: occasionId, rating: 'happy', note: 'Disposable fixture' }],
  ]) {
    const { error } = await admin.from(table).insert(row);
    if (error) throw error;
  }

  const client = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data: signedIn, error: signInError } = await client.auth.signInWithPassword({ email, password });
  if (signInError) throw signInError;
  const requestResponse = await fetch(`${url}/functions/v1/request-account-deletion`, {
    method: 'POST', headers: { authorization: `Bearer ${signedIn.session.access_token}`, apikey: anonKey, 'content-type': 'application/json' }, body: '{}',
  });
  if (requestResponse.status !== 202) throw new Error(`Request endpoint returned ${requestResponse.status}`);
  const { data: deletionRequest, error: deletionRequestError } = await admin
    .from('account_deletion_requests')
    .select('id')
    .eq('user_id', userId)
    .single();
  if (deletionRequestError) throw deletionRequestError;
  deletionRequestId = deletionRequest.id;

  const confirmationUrl = new URL(await pollConfirmationLink());
  const token = confirmationUrl.searchParams.get('token');
  const inspectResponse = await fetch(`${url}/functions/v1/confirm-account-deletion?token=${encodeURIComponent(token)}`, { headers: { apikey: anonKey } });
  if (inspectResponse.status !== 200) throw new Error(`GET inspection returned ${inspectResponse.status}`);
  const before = await admin.auth.admin.getUserById(userId);
  if (!before.data.user) throw new Error('GET inspection deleted the user');

  const confirmResponse = await fetch(`${url}/functions/v1/confirm-account-deletion`, {
    method: 'POST', headers: { apikey: anonKey, 'content-type': 'application/json' }, body: JSON.stringify({ token }),
  });
  const confirmed = await confirmResponse.json();
  if (confirmResponse.status !== 200 || confirmed.status !== 'completed') {
    throw new Error(`POST confirmation did not complete: ${confirmResponse.status} ${confirmed.status}`);
  }
  const authAfter = await admin.auth.admin.getUserById(userId);
  if (authAfter.data.user) throw new Error('Disposable Auth user still exists');
  const { data: profileAfter } = await admin.from('user_info').select('id').eq('id', userId).maybeSingle();
  if (profileAfter) throw new Error('Disposable profile still exists');
  const replay = await fetch(`${url}/functions/v1/confirm-account-deletion`, {
    method: 'POST', headers: { apikey: anonKey, 'content-type': 'application/json' }, body: JSON.stringify({ token }),
  }).then((response) => response.json());
  if (replay.status !== 'already_completed') throw new Error('Token replay was not idempotent');
  const { data: audit, error: auditError } = await admin.from('account_deletion_requests')
    .select('status,user_id,masked_email,token_hash,error_class')
    .eq('id', deletionRequestId)
    .single();
  if (auditError) throw auditError;
  if (audit.status !== 'completed' || audit.user_id || audit.masked_email || audit.token_hash || audit.error_class) {
    throw new Error('Deletion audit retained direct identity or an incomplete state');
  }
  console.log('Disposable account was created, seeded, email-confirmed and deleted locally.');
} finally {
  if (!deletionRequestId && userId) {
    const { data } = await admin.from('account_deletion_requests')
      .select('id').eq('user_id', userId).maybeSingle();
    deletionRequestId = data?.id;
  }
  if (userId) await admin.auth.admin.deleteUser(userId).catch(() => {});
  if (userId) {
    for (const table of [
      'event_feedback', 'event_users_saved', 'event_users', 'occasion_users',
      'organization_users', 'user_info',
    ]) {
      await ignoreCleanupFailure(admin.from(table).delete().eq('user', userId));
    }
    await ignoreCleanupFailure(admin.from('user_info').delete().eq('id', userId));
  }
  if (eventId) await ignoreCleanupFailure(admin.from('events').delete().eq('id', eventId));
  if (occasionId) await ignoreCleanupFailure(admin.from('occasions').delete().eq('id', occasionId));
  if (deletionRequestId) {
    await ignoreCleanupFailure(
      admin.from('account_deletion_requests').delete().eq('id', deletionRequestId),
    );
  }
  for (const id of createdTemplateIds) {
    await ignoreCleanupFailure(admin.from('email_templates').delete().eq('id', id));
  }
  if (createdUnit && unitId) {
    await ignoreCleanupFailure(admin.from('units').delete().eq('id', unitId));
  }
  if (createdOrganization) {
    await ignoreCleanupFailure(admin.from('organizations').delete().eq('id', 9));
  }
}

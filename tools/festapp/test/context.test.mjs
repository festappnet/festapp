import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, reply, actor, profile, activation } from './fixture.mjs';
import { parseProfile, boundedFetch } from '../src/context/profile.mjs';
import { SessionOwner } from '../src/auth/session.mjs';
import { Operations } from '../src/operations/catalog.mjs';

test('activation mismatch makes zero credential or domain calls', async (t) => {
    const f = await fixture(t, {
        fetchImpl: async (url) =>
            url.pathname === '/backend-activation.json'
                ? new Response('{}')
                : undefined,
    });
    await assert.rejects(f.owner.login('fixture@example.invalid', 'test'), {
        code: 'TARGET_MISMATCH',
    });
    assert.equal(f.calls.length, 1);
    assert.equal(f.store.value(), null);
});
test('profiles reject foreign local endpoints and privileged keys', () => {
    const p = profile();
    const { binding, ...raw } = p;
    for (const patch of [
        { backendOrigin: 'http://example.test' },
        { activationUrl: 'http://127.0.0.1:22/manifest' },
        {
            publicApiKey:
                'eyJ.' +
                Buffer.from('{"role":"service_role"}').toString('base64url') +
                '.x',
        },
        { command: 'shell' },
    ])
        assert.throws(() => parseProfile({ ...raw, ...patch }));
});
test('session rotation is serialized across owners and persisted before reads', async (t) => {
    const f = await fixture(t);
    await f.owner.login('fixture@example.invalid', 'test');
    const other = new SessionOwner(f.owner.profile, {
        root: f.owner.root,
        store: f.store,
        fetchImpl: f.owner.fetch,
    });
    const seen = [];
    await Promise.all([
        f.owner.authorized(async () => {
            seen.push(f.store.value().refreshToken);
        }),
        other.authorized(async () => {
            seen.push(f.store.value().refreshToken);
        }),
    ]);
    assert.deepEqual(seen, ['rotated-2', 'rotated-3']);
    assert.equal(
        f.calls.filter((c) => c.url.pathname === '/auth/v1/user').length,
        3,
    );
});
test('foreign organization is denied and never reaches domain commands', async (t) => {
    const f = await fixture(t, {
        fetchImpl: async (url) =>
            url.pathname === '/rest/v1/user_info'
                ? reply({ id: actor, organization: 2 })
                : undefined,
    });
    await assert.rejects(f.owner.login('fixture@example.invalid', 'test'), {
        code: 'TARGET_MISMATCH',
    });
    assert.equal(f.store.value(), null);
    assert(!f.calls.some((c) => c.url.pathname.includes('/rpc/')));
});
test('missing session, strict arguments and logout fail closed without leaked details', async (t) => {
    const f = await fixture(t);
    const ops = new Operations(f.owner);
    assert.equal(
        (await ops.invoke('context.inspect', {})).error.code,
        'AUTHENTICATION_REQUIRED',
    );
    assert.equal(
        (await ops.invoke('context.inspect', { rpc: 'arbitrary' })).error.code,
        'INVALID_INPUT',
    );
    await f.owner.login('fixture@example.invalid', 'test');
    const result = await ops.invoke('context.inspect', {});
    assert.equal(result.ok, true);
    assert.equal(result.data.userId, actor);
    assert(!JSON.stringify(result).includes('rotated-'));
    await f.owner.logout();
    assert.equal(f.store.value(), null);
});
test('activation redirects are prohibited at the network boundary', async () => {
    let redirects;
    const fetcher = boundedFetch(async (_, options) => {
        redirects = options.redirect;
        return new Response(activation);
    });
    await fetcher('https://example.test');
    assert.equal(redirects, 'error');
});
test('MFA challenge is explicit and does not persist a downgraded session', async (t) => {
    const f = await fixture(t, {
        fetchImpl: async (url) =>
            url.pathname === '/auth/v1/user'
                ? reply({
                      id: actor,
                      app_metadata: {},
                      user_metadata: {},
                      factors: [
                          {
                              id: actor,
                              status: 'verified',
                              factor_type: 'totp',
                          },
                      ],
                  })
                : undefined,
    });
    await assert.rejects(f.owner.login('fixture@example.invalid', 'test'), {
        code: 'MFA_REQUIRED',
    });
    assert.equal(f.store.value(), null);
});
test('expired/revoked refresh never reaches identity or domain reads', async (t) => {
    let revoked = false;
    const f = await fixture(t, {
        fetchImpl: async (url) =>
            revoked && url.pathname === '/auth/v1/token'
                ? reply(
                      {
                          code: 'refresh_token_not_found',
                          msg: 'sensitive backend detail',
                      },
                      400,
                  )
                : undefined,
    });
    await f.owner.login('fixture@example.invalid', 'test');
    revoked = true;
    f.calls.length = 0;
    const result = await new Operations(f.owner).invoke('context.inspect', {});
    assert.equal(result.error.code, 'AUTHENTICATION_REQUIRED');
    assert(!JSON.stringify(result).includes('sensitive'));
    assert(
        !f.calls.some(
            (c) =>
                c.url.pathname.includes('/rest/') ||
                c.url.pathname === '/auth/v1/user',
        ),
    );
});
test('failed secure persistence stops domain reads after rotation', async (t) => {
    const f = await fixture(t);
    await f.owner.login('fixture@example.invalid', 'test');
    f.calls.length = 0;
    f.store.write = async () => {
        throw new Error('secure storage failed');
    };
    const result = await new Operations(f.owner).invoke(
        'ticket_layouts.inspect',
        { occasionId: 7 },
    );
    assert.equal(result.ok, false);
    assert(!f.calls.some((c) => c.url.pathname.includes('/rpc/')));
});
test('tenant provisioning reads literal canonical configuration and rejects executable values', async () => {
    const { profileFromTenant } =
        await import('../src/context/tenant-profile.mjs');
    const key =
        'eyJhbGciOiJIUzI1NiJ9.' +
        Buffer.from('{"role":"anon"}').toString('base64url') +
        '.public';
    const text = `WEB_LINK=https://tickets.example.invalid
BACKEND_ACTIVATION_TENANT_ID=fixture
BACKEND_ACTIVATION_PHASE=canonical
BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL=https://api.example.invalid
BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY=${key}
BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID=3
`;
    const p = profileFromTenant(text, 'selected');
    assert.equal(p.organizationId, 3);
    assert.equal(
        p.activationUrl,
        'https://tickets.example.invalid/backend-activation.json',
    );
    assert.throws(() =>
        profileFromTenant(text.replace('canonical\n', 'legacy\n'), 'selected'),
    );
    assert.throws(() =>
        profileFromTenant(text.replace('=3\n', '=$(execute)\n'), 'selected'),
    );
});

import { readFile, writeFile } from 'node:fs/promises';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, reply, profile } from './fixture.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { request, receipt } from './layout-fixture.mjs';
import { FileIntentStore } from '../src/operations/intent-store.mjs';
import { parseProfile } from '../src/context/profile.mjs';
import { canonicalBackendProfileSha256 } from '../../../automation/lib/backend_activation_manifest.mjs';
const endpoint = '/rest/v1/rpc/save_occasion_client_sync_v1';
async function setup(t, respond) {
    let f;
    const sent = [];
    f = await fixture(t, {
        fetchImpl: async (url, init) => {
            if (url.pathname === endpoint) {
                const body = JSON.parse(init.body);
                sent.push(body);
                return respond(body, sent.length, f);
            }
        },
    });
    await f.owner.login('fixture@example.invalid', 'test');
    const ops = new Operations(f.owner);
    await ops.prepare();
    return { ...f, sent, ops };
}
test('durable identity exists before dispatch and exact canonical receipt clears it', async (t) => {
    const f = await setup(t, async (body, _, fixture) => {
        const pending = await new FileIntentStore(fixture.owner.root).read(
            fixture.owner.profile,
            fixture.store.value().userId,
            7,
        );
        assert.equal(pending.commandId, body.p_command_id);
        assert.equal(body.p_expected_version, 3);
        assert.deepEqual(Object.keys(body.p_config).sort(), [
            'id',
            'ticket_layout_change',
        ]);
        return reply(receipt(body.p_command_id));
    });
    const result = await f.ops.invoke(
        'ticket_layouts.save',
        request(f.owner.profile),
    );
    assert.equal(result.ok, true);
    assert.equal(result.data.status, 'applied');
    assert(!JSON.stringify(result).includes('private_data'));
    assert.equal(
        (await f.ops.invoke('ticket_layouts.pending', { occasionId: 7 })).data
            .intent,
        null,
    );
});
test('lost response survives owner/store recreation and resume preserves the original baseline', async (t) => {
    const f = await setup(t, async (body, count) => {
        if (count === 1) throw new Error('response lost');
        return reply(receipt(body.p_command_id, { replayed: true }));
    });
    const input = request(f.owner.profile);
    assert.equal((await f.ops.invoke('ticket_layouts.save', input)).ok, false);
    const reopened = new Operations(f.owner);
    await reopened.prepare();
    const pending = (
        await reopened.invoke('ticket_layouts.pending', { occasionId: 7 })
    ).data.intent;
    assert.equal(pending.request.expectedVersion, 3);
    const changed = await reopened.invoke(
        'ticket_layouts.save',
        request(f.owner.profile, { expectedVersion: 4 }),
    );
    assert.equal(changed.error.code, 'PENDING_RECOVERY_REQUIRED');
    assert.equal(f.sent.length, 1);
    const recovered = await reopened.invoke('ticket_layouts.resume', {
        occasionId: 7,
        commandId: pending.commandId,
    });
    assert.equal(recovered.data.replayed, true);
    assert.deepEqual(f.sent[1], f.sent[0]);
});
for (const variant of ['malformed', 'mismatched', 'expired'])
    test(`${variant} response retains original pending command`, async (t) => {
        const f = await setup(t, async (body) =>
            reply(
                variant === 'malformed'
                    ? { code: 200 }
                    : variant === 'expired'
                      ? { code: 410, mutation: { expired: true } }
                      : receipt('00000000-0000-4000-8000-000000000009'),
            ),
        );
        const input = request(f.owner.profile);
        const result = await f.ops.invoke('ticket_layouts.save', input);
        assert.equal(result.ok, false);
        const pending = (
            await f.ops.invoke('ticket_layouts.pending', { occasionId: 7 })
        ).data.intent;
        assert(pending);
        await f.ops.invoke('ticket_layouts.resume', {
            occasionId: 7,
            commandId: pending.commandId,
        });
        assert.equal(f.sent[0].p_command_id, f.sent[1].p_command_id);
    });
for (const status of ['conflict', 'rejected'])
    test(`confirmed ${status} retires only its original identity`, async (t) => {
        const f = await setup(t, async (body) =>
            reply(
                receipt(body.p_command_id, {
                    status,
                    code: status === 'conflict' ? 409 : 422,
                }),
            ),
        );
        const result = await f.ops.invoke(
            'ticket_layouts.save',
            request(f.owner.profile),
        );
        assert.equal(result.data.status, status);
        assert.equal(
            (await f.ops.invoke('ticket_layouts.pending', { occasionId: 7 }))
                .data.intent,
            null,
        );
    });
test('preview mismatch and strict payload fields are refused before admission', async (t) => {
    const f = await setup(t, () => {
        throw new Error('must not send');
    });
    const input = request(f.owner.profile);
    const changed = structuredClone(input);
    changed.nextLayout.templates = { changed: true };
    assert.equal(
        (await f.ops.invoke('ticket_layouts.save', changed)).error.code,
        'DRAFT_PREVIEW_MISMATCH',
    );
    assert.equal(
        (
            await f.ops.invoke('ticket_layouts.save', {
                ...input,
                title: 'widen',
            })
        ).error.code,
        'INVALID_INPUT',
    );
    assert.equal(f.sent.length, 0);
});
test('old completion cannot erase a newer command; logout preserves recovery state', async (t) => {
    const f = await setup(t, async () => {
        throw new Error('timeout');
    });
    await f.ops.invoke('ticket_layouts.save', request(f.owner.profile));
    const store = new FileIntentStore(f.owner.root),
        user = f.store.value().userId;
    await f.owner.locked(async () => {
        const old = await store.read(f.owner.profile, user, 7);
        assert(await store.clear(f.owner.profile, user, 7, old.commandId));
        const fresh = await store.claim(
            f.owner.profile,
            user,
            request(f.owner.profile, { expectedVersion: 4 }),
        );
        assert.equal(
            await store.clear(f.owner.profile, user, 7, old.commandId),
            false,
        );
        assert.equal(
            (await store.read(f.owner.profile, user, 7)).commandId,
            fresh.commandId,
        );
    });
    await f.owner.logout();
    assert(await store.read(f.owner.profile, user, 7));
});
test('unprepared canonical profiles never advertise or admit the write family', async (t) => {
    const local = profile();
    const { binding, ...raw } = local;
    const value = {
        ...raw,
        kind: 'canonical',
        backendOrigin: 'https://api.example.invalid',
        publicApiKey: 'sb_publishable_fixture',
        activationUrl: 'https://tenant.example.invalid/backend-activation.json',
    };
    value.canonicalProfileSha256 = canonicalBackendProfileSha256({
        tenantId: value.tenantId,
        canonicalOrigin: value.backendOrigin,
        canonicalAnonKey: value.publicApiKey,
        canonicalOrganizationId: value.organizationId,
    });
    const f = await fixture(t, { profileValue: parseProfile(value) });
    const ops = new Operations(f.owner);
    assert.equal(ops.catalog.length, 3);
    assert(!ops.catalog.some((d) => d.id === 'ticket_layouts.save'));
    const result = await ops.invoke(
        'ticket_layouts.save',
        request(f.owner.profile),
    );
    assert.equal(result.error.code, 'FAMILY_NOT_READY');
    assert.equal(f.calls.length, 0);
});

test('corrupted persisted request cannot be rebound to the original command ID', async (t) => {
    const f = await setup(t, async () => {
        throw new Error('timeout');
    });
    await f.ops.invoke('ticket_layouts.save', request(f.owner.profile));
    const store = new FileIntentStore(f.owner.root),
        user = f.store.value().userId;
    const file = await store.path(f.owner.profile, user, 7);
    const original = JSON.parse(await readFile(file, 'utf8'));
    original.request.expectedVersion++;
    await writeFile(file, JSON.stringify(original));
    const result = await f.ops.invoke('ticket_layouts.resume', {
        occasionId: 7,
        commandId: original.commandId,
    });
    assert.equal(result.error.code, 'PENDING_RECOVERY_REQUIRED');
    assert.equal(f.sent.length, 1);
});

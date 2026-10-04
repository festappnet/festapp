import assert from 'node:assert/strict';
import test from 'node:test';
import { DbForms } from '../../src/components/forms/db_forms.js';
import { SupabaseService } from '../../src/services/supabase_service.js';
import { BlueprintRenderer } from '../../src/components/blueprint/blueprint_renderer.js';

test('blueprint loading preserves RPC failures instead of returning null to the renderer', async (t) => {
    t.mock.method(SupabaseService, 'getClient', () => ({
        rpc: async () => ({ data: { code: 400, message: 'Invalid form key or blueprint association.' }, error: null }),
    }));
    await assert.rejects(DbForms.getBlueprint(null, 'form-key', 87), /Invalid form key or blueprint association/);
});

test('blueprint loading preserves transport errors', async (t) => {
    t.mock.method(SupabaseService, 'getClient', () => ({
        rpc: async () => ({ data: null, error: { message: 'Network unavailable' } }),
    }));
    await assert.rejects(DbForms.getBlueprint(null, 'form-key', 87), /Network unavailable/);
});

test('blueprint loading rejects an empty success payload', async (t) => {
    t.mock.method(SupabaseService, 'getClient', () => ({
        rpc: async () => ({ data: { code: 200, data: null }, error: null }),
    }));
    await assert.rejects(DbForms.getBlueprint(null, 'form-key', 87), /Blueprint data unavailable/);
});

test('blueprint loading returns successful seat data', async (t) => {
    const blueprint = { id: 87, objects: [], spots: [] };
    t.mock.method(SupabaseService, 'getClient', () => ({
        rpc: async () => ({ data: { code: 200, data: blueprint }, error: null }),
    }));
    assert.equal(await DbForms.getBlueprint(null, 'form-key', 87), blueprint);
});

test('renderer rejects missing blueprint data before reading meta', () => {
    assert.throws(() => BlueprintRenderer.prototype.render.call({}, null, () => {}), /Blueprint data unavailable/);
});

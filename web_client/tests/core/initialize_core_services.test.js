import assert from 'node:assert/strict';
import test from 'node:test';

import { initializeCoreServices } from '../../src/startup/initialize_core_services.js';

test('loads translations before any service can publish renderable context', async () => {
    const calls = [];
    await initializeCoreServices({
        localizationService: { init: async () => calls.push('localization') },
        supabaseService: { initialize: async () => calls.push('supabase') },
        rightsService: { updateAppData: async () => calls.push('rights') },
        isAppSupported: false,
    });
    assert.deepEqual(calls, ['localization', 'supabase', 'rights']);
});

test('does not fetch unsupported-app context for app-backed tenants', async () => {
    const calls = [];
    await initializeCoreServices({
        localizationService: { init: async () => calls.push('localization') },
        supabaseService: { initialize: async () => calls.push('supabase') },
        rightsService: { updateAppData: async () => calls.push('rights') },
        isAppSupported: true,
    });
    assert.deepEqual(calls, ['localization', 'supabase']);
});

test('public embed keeps backend activation but never initializes organizer rights', async () => {
    const calls = [];
    await initializeCoreServices({
        localizationService: {init: async () => calls.push('localization')},
        supabaseService: {initialize: async () => calls.push('activation and existing session')},
        rightsService: {updateAppData: async () => { throw Error('Organizer rights in embed'); }},
        isAppSupported: false, publicEmbed: true,
    });
    assert.deepEqual(calls, ['localization','activation and existing session']);
});

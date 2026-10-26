import assert from 'node:assert/strict';
import test from 'node:test';

import { LocalizationService } from '../../src/services/localization_service.js';
import { RightsService } from '../../src/services/rights_service.js';
import { SupabaseService } from '../../src/services/supabase_service.js';
import { CommonStrings } from '../../src/components/shared/common_strings.js';

test('critical admin label never exposes its internal translation key', () => {
    const originalTranslations = LocalizationService.translations;
    LocalizationService.translations = {};
    try {
        assert.equal(CommonStrings.admin, 'Admin');
    } finally {
        LocalizationService.translations = originalTranslations;
    }
});

test('critical admin label rejects a legacy self-valued translation', () => {
    const originalTranslations = LocalizationService.translations;
    LocalizationService.translations = { 'FeatureUser.admin': 'FeatureUser.admin' };
    try {
        assert.equal(CommonStrings.admin, 'Admin');
    } finally {
        LocalizationService.translations = originalTranslations;
    }
});

test('rights context is published only after localization is ready', async () => {
    const calls = [];
    const originalGetClient = SupabaseService.getClient;
    const originalLocalizationInit = LocalizationService.init;
    const originalContext = RightsService._context;
    const originalListeners = RightsService._listeners;

    SupabaseService.getClient = () => ({
        rpc: async () => {
            calls.push('rpc');
            return { data: { is_admin: true }, error: null };
        },
    });
    LocalizationService.init = async () => { calls.push('localization'); };
    RightsService._context = null;
    RightsService._listeners = [() => calls.push('render')];

    try {
        assert.equal(await RightsService.updateAppData(), true);
        assert.deepEqual(calls, ['rpc', 'localization', 'render']);
    } finally {
        SupabaseService.getClient = originalGetClient;
        LocalizationService.init = originalLocalizationInit;
        RightsService._context = originalContext;
        RightsService._listeners = originalListeners;
    }
});

test('localization initialization is shared by concurrent callers', async () => {
    const originalInitialization = LocalizationService._initialization;
    const originalInitialize = LocalizationService._initialize;
    let calls = 0;
    let release;
    LocalizationService._initialization = null;
    LocalizationService._initialize = () => {
        calls += 1;
        return new Promise((resolve) => { release = resolve; });
    };

    try {
        const first = LocalizationService.init();
        const second = LocalizationService.init();
        assert.equal(first, second);
        assert.equal(calls, 1);
        release();
        await first;
    } finally {
        LocalizationService._initialization = originalInitialization;
        LocalizationService._initialize = originalInitialize;
    }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { createBrowserStorage } from '../../src/services/browser_storage.js';

test('blocked storage getters support in-page preferences and sessions', () => {
    const storage = createBrowserStorage(() => { throw new Error('SecurityError'); });
    assert.equal(storage.getItem('locale'), null);
    storage.setItem('locale', 'cs');
    assert.equal(storage.getItem('locale'), 'cs');
    storage.removeItem('locale');
    assert.equal(storage.getItem('locale'), null);
});

test('read-only browser storage keeps failed writes consistent within the page', () => {
    const storage = createBrowserStorage(() => ({
        getItem: () => 'old',
        setItem: () => { throw new Error('QuotaExceededError'); },
        removeItem: () => { throw new Error('SecurityError'); },
    }));
    storage.setItem('theme', 'dark');
    assert.equal(storage.getItem('theme'), 'dark');
    storage.removeItem('theme');
    assert.equal(storage.getItem('theme'), null, 'failed removal must not resurrect stale storage');
});

test('normal browser storage remains shared and persistent', () => {
    const values = new Map();
    const native = {
        getItem: key => values.get(key) ?? null,
        setItem: (key, value) => values.set(key, value),
        removeItem: key => values.delete(key),
    };
    const first = createBrowserStorage(() => native);
    const second = createBrowserStorage(() => native);
    first.setItem('auth', 'session');
    assert.equal(second.getItem('auth'), 'session');
    second.removeItem('auth');
    assert.equal(first.getItem('auth'), null);
});

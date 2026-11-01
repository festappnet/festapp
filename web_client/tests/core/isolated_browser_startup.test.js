import test from 'node:test';
import assert from 'node:assert/strict';
import { openIsolatedBrowser } from '../../scripts/isolated_browser_startup.mjs';

function fixture(sessions) {
    const calls = [];
    return {
        calls,
        open: async () => { calls.push('open'); },
        info: async () => { calls.push('info'); return sessions.shift(); },
        close: async () => { calls.push('close'); },
    };
}

test('lost startup daemon is replaced before checking page isolation', async () => {
    const browser = fixture([{ active: false, runtime: null }, { runtime: { pageCount: 1 } }]);
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info', 'close', 'open', 'info']);
});

test('a healthy daemon opens once', async () => {
    const browser = fixture([{ runtime: { pageCount: 1 } }]);
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info']);
});

test('repeated startup loss fails after three task-owned sessions', async () => {
    const browser = fixture(Array.from({ length: 3 }, () => ({ runtime: null })));
    await assert.rejects(openIsolatedBrowser(browser), /daemon disappeared/);
    assert.equal(browser.calls.filter(call => call === 'open').length, 3);
    assert.equal(browser.calls.filter(call => call === 'close').length, 3);
});

test('wrong isolation is a failure, never a startup retry', async () => {
    const browser = fixture([{ runtime: { pageCount: 2 } }]);
    await assert.rejects(openIsolatedBrowser(browser), /isolated local Chromium required/);
    assert.deepEqual(browser.calls, ['open', 'info']);
});

test('navigation errors propagate without retrying page actions', async () => {
    const browser = fixture([]);
    browser.open = async () => { throw new Error('navigation failed'); };
    await assert.rejects(openIsolatedBrowser(browser), /navigation failed/);
    assert.deepEqual(browser.calls, []);
});


test('a launched browser without a page retries only startup before page assertions', async () => {
    const browser = fixture([{ runtime: { pageCount: 0 } }, { runtime: { pageCount: 1 } }]);
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info', 'close', 'open', 'info']);
});

test('repeated empty browser startup is bounded to three fresh sessions', async () => {
    const browser = fixture(Array.from({ length: 3 }, () => ({ runtime: { pageCount: 0 } })));
    await assert.rejects(openIsolatedBrowser(browser), /opened no page/);
    assert.deepEqual(browser.calls, ['open', 'info', 'close', 'open', 'info', 'close', 'open', 'info', 'close']);
});

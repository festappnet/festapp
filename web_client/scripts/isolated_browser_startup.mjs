import assert from 'node:assert/strict';

// A CLI open response can outlive its daemon or its initial page. Recover only
// before exercising the page, with a fresh task-owned session; never retry UI assertions.
export async function openIsolatedBrowser({ open, info, close }, attempts = 3) {
    for (let attempt = 0; attempt < attempts; attempt++) {
        await open();
        const session = await info();
        if (session.runtime != null && session.runtime.pageCount !== 0) {
            assert.equal(session.runtime.pageCount, 1, 'isolated local Chromium required');
            return;
        }
        await close();
    }
    assert.fail('Isolated Chromium daemon disappeared or opened no page during startup after 3 fresh sessions');
}

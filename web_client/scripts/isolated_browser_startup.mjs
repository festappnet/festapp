import assert from 'node:assert/strict';

// A CLI open response can outlive its daemon. Recover only before exercising
// the page, with a fresh task-owned session; never retry failed UI assertions.
export async function openIsolatedBrowser({ open, info, close }, attempts = 3) {
    for (let attempt = 0; attempt < attempts; attempt++) {
        await open();
        const session = await info();
        if (session.runtime != null) {
            assert.equal(session.runtime.pageCount, 1, 'isolated local Chromium required');
            return;
        }
        await close();
    }
    assert.fail('Isolated Chromium daemon disappeared during startup after 3 fresh sessions');
}

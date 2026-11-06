import assert from 'node:assert/strict';

// A CLI open response can outlive its daemon or its initial page. Recover only
// before exercising the page, with a fresh task-owned session; never retry UI assertions.
export async function openIsolatedBrowser({ open, info, close, navigate, currentUrl, targetUrl }, attempts = 3) {
    for (let attempt = 0; attempt < attempts; attempt++) {
        await open();
        const session = await info();
        if (session.runtime != null && session.runtime.pageCount !== 0) {
            assert.equal(session.runtime.pageCount, 1, 'isolated local Chromium required');
            if (!navigate) return;
            await navigate(targetUrl);
            const after = await info();
            const actualUrl = await currentUrl();
            if (after.runtime?.pageCount === 1 && actualUrl === targetUrl) return;
            if (after.runtime?.pageCount > 1) assert.fail('isolated local Chromium required after navigation');
            if (actualUrl && actualUrl !== 'about:blank') {
                assert.fail(`Unexpected browser navigation: expected ${targetUrl}, got ${actualUrl}`);
            }
            await close();
            continue;
        }
        await close();
    }
    assert.fail('Isolated Chromium daemon disappeared, opened no page, or remained blank during startup after 3 fresh sessions');
}

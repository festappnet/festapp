import assert from 'node:assert/strict';

// A CLI open response can outlive its daemon or its initial page. Recover only
// before exercising the page, with a fresh task-owned session; never retry UI assertions.
function lostSetupSession(error) {
    try {
        const report = JSON.parse(error.stdout);
        return report.success === false && /^Failed to install browser network controls: CDP error \(Fetch\.enable\): Session with given id not found\.?$/.test(report.error);
    } catch { return false; }
}

export async function openIsolatedBrowser({ open, info, close, navigate, currentUrl, targetUrl, normalizedUrl, ready }, attempts = 3) {
    for (let attempt = 0; attempt < attempts; attempt++) {
        try {
            try {
                await open();
            } catch (error) {
                // The owned CLI can time out after the daemon has already launched.
                // Probe it below; all other launch failures propagate.
                if (!(error.killed === true && error.signal === 'SIGTERM')) throw error;
            }
            const session = await info();
            if (session.runtime != null && session.runtime.pageCount !== 0) {
                assert.equal(session.runtime.pageCount, 1, 'isolated local Chromium required');
                if (!navigate) {
                    await ready?.();
                    return;
                }
                await navigate(targetUrl);
                const after = await info();
                const actualUrl = await currentUrl();
                if (after.runtime?.pageCount === 1 && (actualUrl === targetUrl || (normalizedUrl && actualUrl === normalizedUrl))) {
                    // Optional read-only initial readiness, before any page actions.
                    await ready?.();
                    return;
                }
                if (after.runtime?.pageCount > 1) assert.fail('isolated local Chromium required after navigation');
                if (actualUrl && actualUrl !== 'about:blank') {
                    assert.fail(`Unexpected browser navigation: expected ${targetUrl}, got ${actualUrl}`);
                }
            }
            await close();
        } catch (error) {
            // The CLI tears down its own browser on this exact setup failure.
            // Real UI assertion failures and errors after startup still propagate.
            if (!lostSetupSession(error)) throw error;
            await close();
        }
    }
    assert.fail(`Isolated Chromium daemon disappeared, opened no page, remained blank, or lost its CDP session during startup after ${attempts} fresh sessions`);
}

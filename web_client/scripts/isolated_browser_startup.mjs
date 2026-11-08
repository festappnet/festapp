import assert from 'node:assert/strict';

// Launch settings belong to a fresh owned session. Re-sending them on every
// CLI call makes agent-browser 0.39.4 reinstall network controls while transient
// cross-origin targets are attaching. The daemon retains the original filter.
export function isolatedBrowserInvocation({launch, session, launchConfig, followConfig, sourceEnv, args}) {
    const config = launch ? launchConfig : followConfig;
    const env = Object.fromEntries(Object.entries(sourceEnv).filter(([key]) => !key.startsWith('AGENT_BROWSER_')));
    Object.assign(env, {AGENT_BROWSER_CONFIG: config, AGENT_BROWSER_PLUGINS:'[]', AGENT_BROWSER_DEFAULT_TIMEOUT:'8000'});
    if (launch && sourceEnv.AGENT_BROWSER_EXECUTABLE_PATH) {
        env.AGENT_BROWSER_EXECUTABLE_PATH = sourceEnv.AGENT_BROWSER_EXECUTABLE_PATH;
    }
    return {
        args:['--config',config,'--namespace',session,'--session',session,'--json',
            ...(launch ? ['--headed','false','--allowed-domains','127.0.0.1,localhost'] : []), ...args],
        env,
    };
}

// A CLI open response can outlive its daemon or its initial page. Recover only
// before exercising the page, with a fresh task-owned session; never retry UI assertions.
function lostSetupSession(error) {
    try {
        const report = JSON.parse(error.stdout);
        return report.success === false && /^Failed to install browser network controls: CDP error \(Fetch\.enable\): Session with given id not found\.?$/.test(report.error);
    } catch { return false; }
}

export async function openIsolatedBrowser({ open, info, close, navigate, currentUrl, waitForNavigation, targetUrl, normalizedUrl, ready }, attempts = 3) {
    for (let attempt = 0; attempt < attempts; attempt++) {
        let observation;
        try {
            try {
                await open();
            } catch (error) {
                // The owned CLI can time out after the daemon has already launched.
                // Probe it below; all other launch failures propagate.
                if (!(error.killed === true && error.signal === 'SIGTERM')) throw error;
            }
            const session = await info();
            observation = {stage:'launch', pageCount:session.runtime?.pageCount ?? null, browserLaunched:session.runtime?.browserLaunched ?? null};
            if (session.runtime != null && session.runtime.pageCount !== 0) {
                assert.equal(session.runtime.pageCount, 1, 'isolated local Chromium required');
                if (!navigate) {
                    await ready?.();
                    return;
                }
                await navigate(targetUrl);
                let after = await info();
                let actualUrl = after.runtime?.pageCount === 1 ? await currentUrl() : null;
                observation = {stage:'navigation', pageCount:after.runtime?.pageCount ?? null, browserLaunched:after.runtime?.browserLaunched ?? null, urlState:actualUrl === 'about:blank' ? 'blank' : actualUrl ? 'nonblank' : 'missing'};
                // Chrome may report a live blank tab immediately after a
                // navigation command while the destination is still committing.
                // Wait for that already-started navigation only; never retry
                // an interaction or accept an unexpected final URL.
                if (after.runtime?.pageCount === 1 && actualUrl === 'about:blank' && waitForNavigation) {
                    await waitForNavigation(targetUrl);
                    after = await info();
                    actualUrl = after.runtime?.pageCount === 1 ? await currentUrl() : null;
                    observation = {stage:'navigation-wait', pageCount:after.runtime?.pageCount ?? null, browserLaunched:after.runtime?.browserLaunched ?? null, urlState:actualUrl === 'about:blank' ? 'blank' : actualUrl ? 'nonblank' : 'missing'};
                }

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
            // Keep the actual pre-close evidence; querying the closed session
            // later can launch a fresh blank browser and obscure the failure.
            console.error('Isolated browser setup lost:', JSON.stringify({attempt:attempt + 1, ...observation}));
            await close();
        } catch (error) {
            // The CLI tears down its own browser on this exact setup failure.
            // Real UI assertion failures and errors after startup still propagate.
            if (!lostSetupSession(error)) throw error;
            console.error('Isolated browser setup lost:', JSON.stringify({attempt:attempt + 1, ...observation, reason:'cdp-network-setup'}));
            await close();
        }
    }
    assert.fail(`Isolated Chromium daemon disappeared, opened no page, remained blank, or lost its CDP session during startup after ${attempts} fresh sessions`);
}

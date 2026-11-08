#!/usr/bin/env node
// Render the real production HTML shell and Main entrypoint in isolated Chromium.
// Backend transport is fixture data; Google cryptography/SQL has a separate gate.
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer as createPortProbe } from 'node:net';
import { createServer } from 'vite';
import { isolatedBrowserInvocation, openIsolatedBrowser } from './isolated_browser_startup.mjs';
import { testPwaSplitBrowser } from './test_pwa_split_browser.mjs';
const execute = promisify(execFile);
const root = path.resolve(import.meta.dirname, '..');
const temporary = await mkdtemp(path.join(tmpdir(), 'festapp-form-access-'));
const config = path.join(temporary, 'browser.json');
const darkConfig = path.join(temporary, 'browser-dark.json');
const followConfig = path.join(temporary, 'browser-follow.json');
await writeFile(config, JSON.stringify({ provider: null, plugins: [], headed: false, autoConnect: false, args: '--mute-audio', colorScheme: 'light' }));
await writeFile(darkConfig, JSON.stringify({ provider: null, plugins: [], headed: false, autoConnect: false, args: '--mute-audio', colorScheme: 'dark' }));
await writeFile(followConfig, JSON.stringify({ provider: null, plugins: [], autoConnect: false }));
let browserIndex = 0;
let session = `fa-${process.pid}`;
let browserPhase = 'setup';
const requests = [];
let needsLaunch = false;
let launchConfig = config;
async function browser(...args) {
    const launch = needsLaunch;
    needsLaunch = false;
    const invocation = isolatedBrowserInvocation({launch, session, launchConfig, followConfig, sourceEnv:process.env, args});
    const { stdout } = await execute('agent-browser', invocation.args, {timeout:30000, env:invocation.env});
    const result = JSON.parse(stdout);
    assert.equal(result.success, true, result.error);
    const lifecycle = result.data?.lifecycle;
    if (!launch && (lifecycle?.launched || lifecycle?.relaunchedBrowser || lifecycle?.restartedBackground)) {
        throw new Error('Owned browser restarted after launch; refusing to continue without its original launch controls');
    }
    return result.data;
}
async function openBrowser(url, ready) {
    // The fixture consumes this selector before the real router strips it.
    const normalizedUrl=new URL(url);normalizedUrl.searchParams.delete('scenario');
    await openIsolatedBrowser({
        open: async () => {
            session = `fa-${process.pid}-${++browserIndex}`;
            needsLaunch = true;
            browserPhase = 'launch';
            // Verify a ready, isolated browser before starting page navigation.
            // A combined cold launch/navigation can otherwise hide which stage
            // stalled, and prevents the existing empty-daemon recovery check.
            await browser('open', new URL('/__browser_startup', url).href);
        },
        info: () => browser('session', 'info'),
        close: () => browser('close'),
        navigate: target => { browserPhase = 'navigation'; return browser('open', target); },
        currentUrl: async () => (await browser('get', 'url')).url,
        waitForNavigation: target => { const expected = new URL(target); return browser('wait', '--url', `${expected.origin}${expected.pathname}*`); },
        targetUrl: url,
        normalizedUrl: normalizedUrl.href,
        ready,
    });
    browserPhase = 'page assertions';
}
let server;
let versionRequests = 0;
try {
    const shell = (await readFile(path.join(root, 'index.html'), 'utf8'))
        .replace('<head>', `<head><script>if (new URLSearchParams(location.search).get('scenario') === 'embed-pending') localStorage.setItem('theme', new URLSearchParams(location.search).get('saved') || 'dark');</script>`)
        .replace('src="/src/main.js"', 'src="/tests/fixtures/form_access/main.js"')
        .replace('</head>', `<script>
            const initialScenario = new URLSearchParams(location.search).get('scenario');
            if (initialScenario === 'embed-update-pristine' || initialScenario === 'embed-update-dirty') {
                sessionStorage.setItem('fixtureUpdateScenario', initialScenario);
            }
            const fixtureScenario = initialScenario || sessionStorage.getItem('fixtureUpdateScenario');
            if (fixtureScenario === 'embed-update-pristine' || fixtureScenario === 'embed-update-dirty') {
                new MutationObserver(() => {
                    if (document.getElementById('festapp-update-banner')) {
                        window.parent.postMessage({fixtureBannerObserved:true}, '*');
                    }
                }).observe(document.documentElement, {childList:true, subtree:true});
                const register = navigator.serviceWorker.register.bind(navigator.serviceWorker);
                navigator.serviceWorker.register = (url, options) => register('/__fixture-update-worker.js', options);
                navigator.serviceWorker.addEventListener('message', event => {
                    if (event.data === 'fixture-worker-query-pending') {
                        window.parent.postMessage({fixtureUpdateReport:{workerQueryPending:true}}, '*');
                    }
                });
            }
            if (fixtureScenario === 'embed-pending') {
                let sampledFrames=0, paintedLoader=false, logoSeen=false, logoLoaded=false, logoContained=true, transparentStartup=true;
                const childCanvases = new Set(), logoSources = new Set(), logoFilters = new Set();
                function samplePendingPaint() {
                    if (window.__fixtureFormPending) {
                        sampledFrames++;
                        const probe=document.createElement('i');
                        probe.style.color='Canvas'; probe.style.display='none';
                        document.documentElement.append(probe);
                        childCanvases.add(getComputedStyle(probe).color);
                        probe.remove();
                    }
                    if (window.__FESTAPP_APP_READY__ !== true) {
                        const startup=document.querySelector('#web-client-startup');
                        if (startup && getComputedStyle(startup).backgroundColor !== 'rgba(0, 0, 0, 0)') transparentStartup=false;
                        const logo=startup?.querySelector('.startup-brand');
                        if (logo) {
                            const r=logo.getBoundingClientRect(); let shown=r.width>0 && r.height>0;
                            for (let node=logo; shown && node; node=node.parentElement) {
                                const style=getComputedStyle(node);
                                shown=style.display!=='none' && style.visibility!=='hidden' && Number(style.opacity)!==0;
                            }
                            if (shown) {
                                logoSeen=true; logoLoaded ||= logo.complete && logo.naturalWidth>0;
                                logoContained &&= r.height<=48 && r.width<=48 && r.width<=innerWidth && r.top>=24 && innerHeight-r.bottom>=24;
                                logoSources.add(new URL(logo.src, location.href).pathname);
                                logoFilters.add(getComputedStyle(logo).filter);
                            }
                        }
                        const loader=document.querySelector('#form-page-container .sp-loader');
                        if (loader) {
                            const rect=loader.getBoundingClientRect();
                            let visible=rect.width>0 && rect.height>0;
                            for (let node=loader; visible && node; node=node.parentElement) {
                                const style=getComputedStyle(node);
                                visible=style.display!=='none' && style.visibility!=='hidden' && Number(style.opacity)!==0;
                            }
                            paintedLoader ||= visible;
                        }
                    }
                    requestAnimationFrame(samplePendingPaint);
                }
                requestAnimationFrame(samplePendingPaint);
                window.addEventListener('message', event => {
                    if (event.data === 'fixture-release-form') { window.__fixtureReleaseForm?.(); return; }
                    if (event.data !== 'fixture-pending-query') return;
                    const deadline=performance.now()+2000;
                    function replyWhenSampled() {
                        if ((!window.__fixtureFormPending || sampledFrames < 2 || !logoLoaded) && performance.now()<deadline) { requestAnimationFrame(replyWhenSampled); return; }
                        event.source.postMessage({fixtureUpdateReport:{pending:!!window.__fixtureFormPending, sampledFrames, paintedLoader, logoSeen, logoLoaded, logoContained, transparentStartup, logoSources:[...logoSources], logoFilters:[...logoFilters], childCanvases:[...childCanvases]}}, event.origin);
                    }
                    replyWhenSampled();
                });
            }
            if (new URLSearchParams(location.search).get('scenario') === 'embed-error') {
                Object.defineProperty(navigator, 'onLine', {value:false, configurable:true});
                window.addEventListener('message', event => {
                    if (event.data !== 'fixture-error-check') return;
                    const button = document.querySelector('#web-client-startup button');
                    const rect = button?.getBoundingClientRect();
                    event.source.postMessage({fixtureUpdateReport:{failed:!!window.__FESTAPP_WEB_STARTUP_FAILURE__,
                        buttonVisible:!!button && !button.hidden && rect.top >= 0 && rect.bottom <= innerHeight,
                        enabled:!!button && !button.disabled, text:document.querySelector('#web-client-startup p')?.textContent,
                        banner:!!document.getElementById('festapp-update-banner')}}, event.origin);
                });
            }
            if (new URLSearchParams(location.search).get('scenario')?.startsWith('embed-')) {
                const originalFetch = window.fetch;
                window.fetch = function(input, init) {
                    const response = originalFetch.call(this, input, init);
                    if (new URLSearchParams(location.search).get('scenario') === 'embed-pending' &&
                        String(input).includes('/__form_access_rpc') && JSON.parse(init?.body || '{}').name === 'get_form_by_link') {
                        return response.then(value => new Promise(resolve => {
                            window.__fixtureFormPending = true;
                            window.__fixtureReleaseForm = () => { window.__fixtureFormPending = false; resolve(value); };
                        }));
                    }
                    if (!String(input).includes('/festapp-version.json?t=')) return response;
                    return response.then(value => new Promise(resolve => {
                        window.__fixtureVersionPending = true;
                        window.__fixtureReleaseVersion = () => { window.__fixtureVersionPending = false; resolve(value); };
                    }));
                };
            }
        </script><script src="/__fixture-update.js"></script></head>`);
    // Vite treats port 0 as its default port; select a free positive port first.
    const portProbe = createPortProbe();
    await new Promise((resolve, reject) => {
        portProbe.once('error', reject);
        portProbe.listen(0, '127.0.0.1', resolve);
    });
    const { port } = portProbe.address();
    await new Promise((resolve, reject) => portProbe.close(error => error ? reject(error) : resolve()));
    server = await createServer({ root, configFile: false, logLevel: 'error', server: { host: '127.0.0.1', port, strictPort: true },
        plugins: [{ name: 'form-access-fixture', configureServer(server) {
            server.middlewares.use((req, res, next) => {
                const record = { path: req.url.split('?')[0], state: 'pending' };
                requests.push(record);
                if (requests.length > 30) requests.shift();
                res.once('finish', () => { record.state = res.statusCode; });
                next();
            });
            server.middlewares.use(async (req, res, next) => {
                if (req.url.startsWith('/__missing_entry.js')) {
                    res.statusCode = 404; res.setHeader('Content-Type', 'text/plain'); res.end('missing fixture'); return;
                }
                if (req.url === '/__fixture-update-worker.js') {
                    res.setHeader('Content-Type', 'application/javascript');
                    res.end(`let pending;
                        self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
                        self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
                        self.addEventListener('message', event => {
                            if (event.data?.type === 'FESTAPP_QUERY_BUILD_VERSION') {
                                pending = event.ports[0];
                                event.source.postMessage('fixture-worker-query-pending');
                            } else if (event.data === 'fixture-release-worker' && pending) {
                                pending.postMessage({version:'fixture-new-version',runtime:'web',ready:true});
                                pending = null;
                            }
                        });`); return;
                }
                if (req.url === '/festapp_service_worker.js') {
                    res.setHeader('Content-Type', 'application/javascript');
                    res.end(await readFile(path.join(root, 'tests/fixtures/form_access/service_worker.js'))); return;
                }
                if (req.url.startsWith('/__fixture-update.js')) {
                    res.setHeader('Content-Type', 'application/javascript');
                    res.end(await readFile(path.join(root, '../web/festapp_update_prompt.js'))); return;
                }
                if (req.url.startsWith('/festapp-version.json')) {
                    versionRequests++;
                    res.setHeader('Content-Type', 'application/json');
                    res.end(JSON.stringify({version:'fixture-new-version'})); return;
                }
                if (req.url.startsWith('/__real_embed_host')) {
                    const params = new URL(req.url, 'http://localhost').searchParams;
                    const helper = params.get('helper') === 'legacy' ? '/tests/fixtures/form_access/embed-main-06671ad.js'
                        : params.get('helper') === 'pr769' ? '/tests/fixtures/form_access/embed-pr769-987574b.js' : '/embed.js';
                    const child = `http://localhost:${server.httpServer.address().port}/form/account-access?embed=1&scenario=${params.get('scenario') || 'embed-short'}&saved=${params.get('saved') || 'dark'}`;
                    const fixed = params.get('fixed') === '1';
                    res.setHeader('Content-Type', 'text/html');
                    res.end(`<!doctype html><html><body style="margin:0;background:${params.get('palette') === 'dark' ? '#202020;color:#fff' : '#f2f2f2;color:#111'}"><header style="height:100px">Pořadatel</header><iframe data-festapp-embed ${fixed ? 'data-festapp-height="fixed"' : ''} src="${child}" style="width:100%;${fixed ? 'height:300px;max-height:300px' : ''}" height="${fixed ? 300 : 800}" title="Přihláška"></iframe><script>window.fixtureFrameLoads=0;window.fixtureBannerObserved=false;window.addEventListener("message",e=>{if(e.data?.fixtureBannerObserved)window.fixtureBannerObserved=true});document.querySelector("iframe").addEventListener("load",()=>window.fixtureFrameLoads++);window.addEventListener("message",e=>{if(e.data?.fixtureUpdateReport)window.fixtureUpdateReport=e.data.fixtureUpdateReport})</script>${params.get('helper') === 'none' ? '' : `<script src="${helper}"></script>`}</body></html>`); return;
                }
                if (req.url === '/__browser_startup') {
                    res.setHeader('Content-Type', 'text/html'); res.end('<!doctype html><title>Browser startup</title>'); return;
                }
                if (req.url.startsWith('/form/price-position')) {
                    res.setHeader('Content-Type','text/html');
                    res.end('<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><main id="form-page-container"><div class="form-header"><h1>Weekend registration</h1><p><a href="#">https://example.invalid/RegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaksRegistrationCodeWithoutBreaks</a></p></div><form id="dynamic-form"><div style="height:2400px"></div><button type="submit">Continue</button></form></main><script type="module" src="/tests/fixtures/form_access/price_position.js"></script></body></html>');return;
                }
                if (req.url.startsWith('/__price_position_host')) {
                    const params=new URL(req.url,'http://localhost').searchParams;
                    const native=params.get('native')==='1';
                    const palette=params.get('palette');
                    const colors=palette==='oklch' ? 'color:white;background:oklch(0.25 0.05 260)'
                        : palette==='p3' ? 'color:white;background:color(display-p3 0.1 0.2 0.3)' : '';
                    res.setHeader('Content-Type','text/html');
                    res.end(`<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0;${colors}}iframe{display:block;width:100%;border:0}header{height:300px}footer{height:600px}</style></head><body><header>Organizer website</header><div ${native?'data-festapp-embed-host':''}><iframe data-festapp-embed src="/form/price-position?embed=1" height="800" title="Registration"></iframe></div><footer>Footer</footer><script src="/embed.js"></script></body></html>`);return;
                }
                if (req.url.startsWith('/form/account-access') || req.url === '/' || req.url.startsWith('/?')) {
                    res.setHeader('Content-Type', 'text/html');
                    res.end(req.url.includes('scenario=embed-error')
                        ? shell.replace('/tests/fixtures/form_access/main.js', '/__missing_entry.js')
                        : shell); return;
                }
                if (/^\/assets\/translations\/(cs|en)\.json$/.test(req.url)) {
                    res.setHeader('Content-Type', 'application/json');
                    res.end(await readFile(path.join(root, '..', req.url.slice(1)))); return;
                }
                if (req.url.startsWith('/functions/v1/google-auth-start')) {
                    res.setHeader('Content-Type', 'text/html');
                    res.end('<h1 data-provider-boundary>Google provider handoff</h1>'); return;
                }
                if (req.url !== '/__form_access_rpc') return next();
                let body = ''; for await (const chunk of req) body += chunk;
                const { name, args, scenario } = JSON.parse(body);
                if (name === 'get_form_measurement_policy') {
                    res.setHeader('Content-Type', 'application/json');
                    res.end(JSON.stringify({data:{eligible:false, enabled:false}, error:null})); return;
                }
                const editor = scenario.startsWith('editor') || scenario.startsWith('unit-editor');
                let data;
                if (name === 'get_app_config_v218') data = {
                    organization: { IS_REGISTRATION_ENABLED: true },
                    user_info: editor ? { id: 'fixture-user', name: 'Editor' } : null,
                    occasion: { link: 'fixture-event' },
                    occasion_user: { is_editor_order_view: scenario.startsWith('editor') },
                    unit_user: { is_editor_view: scenario.startsWith('unit-editor') },
                    capabilities: { 'orders.read': editor, 'navigation.admin_web': editor },
                };
                else if (name === 'get_form_by_link') data = { code: 200, data: {
                    id: 1, link: 'account-access', title: 'Account access regression',
                    data: {design:{embed_inherit_style:true}},
                    is_open: !scenario.endsWith('closed'), header: '<p>Registration details</p>',
                    fields: [{ id: 1, type: 'email', title: 'E-mail', is_required: true },
                        ...(scenario.startsWith('embed-') ? [{id:2, type:'birth_date', title:'Datum narození', is_required:true},
                            ...(scenario === 'embed-long' ? Array.from({length:18}, (_,i) => ({id:i+3,type:'text',title:`Otázka ${i+1}`,is_required:false})) : [])] : [])],
                } };
                else if (name === 'get_available_occasions') data = [];
                else if (name === 'google-auth-start') data = args.operation === 'capability'
                    ? { enabled: true } : { attempt: 'fixture-attempt', url: `http://${req.headers.host}/functions/v1/google-auth-start?bootstrap=fixture` };
                else throw new Error(`Unexpected fixture request: ${name}`);
                res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ data, error: null }));
            });
        } }] });
    await server.listen();
    const origin = `http://127.0.0.1:${server.httpServer.address().port}`;
    const visible = selector => `(() => { const e=document.querySelector(${JSON.stringify(selector)}); if(!e)return false; const r=e.getBoundingClientRect(); return r.width>0 && r.height>0 && getComputedStyle(e).visibility!=='hidden'; })()`;
    // Hold the public form response after transport completes, so the real
    // shell/Main/child can paint while form data is still pending. No order or
    // subscription is submitted. The existing offline retry case stays below.
    for (const [palette, preference] of [['light','dark'], ['dark','light'], ['light','light'], ['dark','dark']]) {
        launchConfig = preference === 'dark' ? darkConfig : config;
        const saved = palette === 'dark' ? 'light' : 'dark';
        await openBrowser(`${origin}/__real_embed_host?scenario=embed-pending&helper=current&fixed=0&palette=${palette}&saved=${saved}`);
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-pending-query", "*")');
        await browser('wait', '--fn', 'window.fixtureUpdateReport?.pending && window.fixtureUpdateReport?.sampledFrames >= 2');
        const pendingPaint = (await browser('eval', 'window.fixtureUpdateReport')).result;
        assert.equal(pendingPaint.paintedLoader, false, 'embedded form must not paint its animated pending loader');
        assert.equal(pendingPaint.logoSeen, true, 'embedded startup must display its branded loader');
        assert.equal(pendingPaint.logoLoaded, true, 'embedded startup symbol must load');
        assert.equal(pendingPaint.logoContained, true, 'embedded symbol must fit within 48px with 24px vertical breathing room');
        assert.deepEqual(pendingPaint.logoSources, ['/brand-symbol.svg'], 'embedded startup must show the standalone symbol only');
        assert.ok(pendingPaint.logoFilters.every(filter => filter.includes('brightness(0)') && (palette === 'dark' ? filter.includes('invert(1)') : !filter.includes('invert(1)'))),
            'embedded symbol must be monochrome and contrast with the host theme');
        assert.equal(pendingPaint.transparentStartup, true, 'embedded startup background must remain transparent');
        const iframeCanvas = (await browser('eval', `(() => {
            const probe=document.createElement('i'); probe.style.color='Canvas';
            probe.style.colorScheme=getComputedStyle(document.querySelector('iframe')).colorScheme;
            document.body.append(probe); const color=getComputedStyle(probe).color; probe.remove(); return color;
        })()`)).result;
        assert.deepEqual(pendingPaint.childCanvases, [iframeCanvas], 'embedded child and host iframe must use the same canvas color during startup');
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-release-form", "*")');
        await browser('snapshot', '-i');
        await browser('frame', '@e1');
        await browser('wait', 'input[type=email]');
        await browser('frame', 'main');
        await browser('eval', `document.querySelector("iframe").contentWindow.postMessage({type:"fixture-theme-check",dark:${palette === 'dark'}}, "*")`);
        await browser('wait', '--fn', 'window.fixtureUpdateReport?.themeMatch === true');
        await browser('eval', `document.body.style.backgroundColor=${JSON.stringify(palette === 'dark' ? '#f2f2f2' : '#202020')}`);
        await browser('eval', `document.querySelector("iframe").contentWindow.postMessage({type:"fixture-theme-check",dark:${palette !== 'dark'}}, "*")`);
        await browser('wait', '--fn', `window.fixtureUpdateReport?.themeMatch === true && window.fixtureUpdateReport?.dark === ${palette !== 'dark'}`);
        await browser('close');
        console.log(`PASS: ${palette} host, ${preference} browser, opposite saved theme, startup logo and dynamic host theme`);

    }
    launchConfig = config;

    // Exercise the actual updater while a matching worker's readiness response is
    // held. Only transport is simulated; typing uses trusted browser input.
    for (const dirty of [false, true]) {
        const scenario = dirty ? 'embed-update-dirty' : 'embed-update-pristine';
        await openBrowser(`${origin}/__real_embed_host?scenario=${scenario}&helper=current&fixed=0`);
        await browser('snapshot', '-i');
        await browser('frame', '@e1');
        await browser('wait', 'input[type=email]');
        await browser('frame', 'main');
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-start-update", "*")');
        await browser('wait', '--fn', 'window.fixtureUpdateReport?.workerQueryPending === true');
        if (dirty) {
            await browser('snapshot', '-i');
            await browser('frame', '@e1');
            await browser('fill', 'input[type=email]', 'rozpracovano@example.test');
            await browser('frame', 'main');
        }
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-release-worker", "*")');
        if (dirty) {
            await browser('wait', '500');
            assert.equal((await browser('eval', 'window.fixtureFrameLoads')).result, 1, 'dirty form must not reload');
            await browser('snapshot', '-i');
            await browser('frame', '@e1');
            assert.equal((await browser('get', 'value', 'input[type=email]')).value, 'rozpracovano@example.test');

        } else {
            await browser('wait', '--fn', 'window.fixtureFrameLoads >= 2');
            await browser('snapshot', '-i');
            await browser('frame', '@e1');
            await browser('wait', 'input[type=email]');

        }
        await browser('frame', 'main');
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-inspect-update", "*")');
        await browser('wait', '--fn', 'window.fixtureUpdateReport?.inspection === true');
        const inspection = (await browser('eval', 'window.fixtureUpdateReport')).result;
        assert.equal(inspection.banner, false, 'embedded document must not show an update banner');
        assert.equal((await browser('eval', 'window.fixtureBannerObserved')).result, false, 'update banner must never be painted');
        if (dirty) assert.equal(inspection.draft, 'rozpracovano@example.test');
        console.log(`PASS: ${dirty ? 'dirty draft protected during worker preparation' : 'pristine embedded form automatically updated without banner'}`);
        await browser('close');
    }

    // Real shell, Main and form in a cross-origin host with the shipped and
    // frozen PR 769 helpers. Backend transport and the version response alone
    // are fixtures; the updater starts before the delayed Main import.
    let verifiedHostSessions = 0;
    for (const [scenario, helper, fixed, width] of [
        ['embed-long', 'none', 0, 320], ['embed-short', 'current', 0, 320],
        ['embed-long', 'pr769', 0, 390], ['embed-long', 'legacy', 0, 1440],
        ['embed-long', 'legacy', 1, 390],
    ]) {
        const before = versionRequests;
        await openBrowser(`${origin}/__real_embed_host?scenario=${scenario}&helper=${helper}&fixed=${fixed}`, async () => {
            // Viewport setup and the first read-only frame check are still
            // pre-interaction startup. A detached CDP setup session here can
            // use the launcher's bounded fresh-session recovery.
            await browser('set', 'viewport', String(width), '844');
            await browser('wait', '--fn', fixed ? 'document.querySelector("iframe").clientHeight === 300' : helper === 'none' ? 'document.querySelector("iframe").clientHeight === 800' : 'document.querySelector("iframe").clientHeight > 240');
        });
        // The launch-only domain filter must still reject disallowed loopback
        // hosts after crossing origins; no request leaves the browser.
        if (verifiedHostSessions++ < 2) {
            const denied = (await browser('eval', `fetch('http://127.0.0.2:${server.httpServer.address().port}/blocked').then(()=>'allowed',e=>e.name)`)).result;
            assert.equal(denied, 'SecurityError', 'launch-time network containment must persist');
        }
        await browser('snapshot', '-i');
        await browser('frame', '@e1');
        await browser('wait', '.flatpickr-input + input');
        await browser('click', '.btn-submit');
        await browser('frame', 'main');
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-check-validation", "*")');
        await browser('wait', '--fn', 'window.fixtureUpdateReport?.validationShown === true');
        await browser('snapshot', '-i');
        await browser('frame', '@e1');
        await browser('fill', 'input[type=email]', 'rozpracovano@example.test');
        await browser('click', '.flatpickr-input + input');
        await browser('wait', '.flatpickr-calendar.open');
        await browser('click', '.flatpickr-day:not(.prevMonthDay):not(.nextMonthDay)');
        assert.ok((await browser('get', 'value', '.flatpickr-input')).value);
        assert.equal((await browser('get', 'value', 'input[type=email]')).value, 'rozpracovano@example.test');
        await browser('frame', 'main');
        await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-check-update", "*")');
        await browser('wait', '--fn', 'window.fixtureUpdateReport?.ready && window.fixtureUpdateReport?.versionWasPending && !window.fixtureUpdateReport?.readyAtFocus && window.fixtureUpdateReport?.draft === "rozpracovano@example.test" && !window.fixtureUpdateReport?.banner');
        assert.ok(versionRequests > before, 'updater must execute a production version request before readiness');
        if (fixed || helper === 'none') assert.equal((await browser('eval', 'document.querySelector("iframe").clientHeight')).result, fixed ? 300 : 800);
        else if (scenario === 'embed-long') await browser('wait', '--fn', 'document.querySelector("iframe").clientHeight > 1200');
        console.log(`PASS: real ${scenario}, ${helper} helper at ${width}px, cross-origin ${fixed ? 'fixed' : 'resizing'} frame, validation, calendar and update draft`);
        await browser('close');
    }
    // Exercise the actual HTML failure UI while the helper's startup height is
    // still in effect. A 404 keeps both retry attempts local and non-mutating.
    await openBrowser(`${origin}/__real_embed_host?scenario=embed-error&helper=current&fixed=0`);
    await browser('snapshot', '-i');
    await browser('frame', '@e1');
    await browser('wait', '#web-client-startup button');
    await browser('click', '#web-client-startup button');
    await browser('wait', '#web-client-startup button:not([disabled])');
    await browser('click', '#web-client-startup button');
    await browser('wait', '#web-client-startup button:not([disabled])');
    await browser('frame', 'main');
    assert.equal((await browser('eval', 'document.querySelector("iframe").clientHeight')).result, 120);
    await browser('eval', 'document.querySelector("iframe").contentWindow.postMessage("fixture-error-check", "*")');
    await browser('wait', '--fn', 'window.fixtureUpdateReport?.failed && window.fixtureUpdateReport?.buttonVisible && window.fixtureUpdateReport?.enabled && !!window.fixtureUpdateReport?.text && !window.fixtureUpdateReport?.banner');
    console.log('PASS: real failed embed startup exposes retry inside the frame after two attempts');
    await browser('close');
    await testPwaSplitBrowser({browser, openBrowser, temporary});
    for (const scenario of ['guest-open', 'editor-open', 'editor-closed', 'unit-editor-open', 'unit-editor-closed', 'visitor-closed']) {
        await openBrowser(`${origin}/form/account-access?scenario=${scenario}`);
        await browser('wait', '--fn', '!document.getElementById("web-client-startup")');
        await browser('wait', '--fn', `!(${visible('#universal-header')})`);
        await browser('wait', '--fn', visible('#form-page-container'));
        assert.equal((await browser('get', 'count', '#universal-header')).count, 1);
        const editor = scenario.startsWith('editor') || scenario.startsWith('unit-editor');
        if (!scenario.endsWith('closed')) await browser('wait', '--fn', visible('#dynamic-form input'));
        if (editor) {
            await browser('wait', '--fn', visible('.fab-edit'));
            assert.equal((await browser('get', 'count', '.fab-edit')).count, 1);
            await browser('click', '.fab-edit');
            await browser('wait', '--fn', 'window.__adminDestination === "/fixture-event/reservations"');
        } else {
            assert.equal((await browser('get', 'count', '.fab-edit')).count, 0, 'visitors must not receive editor controls');
        }
        if (scenario === 'guest-open') await browser('set', 'viewport', '390', '844');
        console.log(`PASS: ${scenario} - visible form, hidden site header and permitted editor access`);
        // Each identity gets a fresh browser and daemon namespace. Avoid both
        // detached navigation targets and reconnecting to a closing daemon.
        await browser('close');
    }
    // A long editor link must not widen the mobile layout viewport, which
    // otherwise moves the fixed price beyond the visible screen on Android.
    for (const width of [390,1280]) {
        for (const presentation of ['regular','native-embed','legacy-embed']) {
            const url=presentation==='regular' ? `${origin}/form/price-position`
                : `${origin}/__price_position_host?native=${presentation==='native-embed'?1:0}`;
            await openBrowser(url);
            await browser('set','viewport',String(width),'844');
            const selector=presentation==='native-embed' ? '[data-festapp-embed-price] button' : '#floating-price-widget';
            await browser('wait','--fn',presentation==='regular'
                ? '!!document.getElementById("floating-price-widget")'
                : 'document.querySelector("iframe").clientHeight > 2000');
            if(presentation==='native-embed') await browser('wait',selector);
            if(presentation!=='regular') await browser('wait','--fn',`(() => {
                const frame=document.querySelector('iframe');
                const doc=frame.contentDocument;
                const heading=doc.querySelector('.form-header');
                const price=${presentation==='native-embed' ? 'document.querySelector("[data-festapp-embed-price] button")' : 'doc.getElementById("floating-price-widget")'};
                if(!heading || !price)return false;
                const priceBottom=price.getBoundingClientRect().bottom+${presentation==='legacy-embed' ? 'frame.getBoundingClientRect().top' : '0'};
                return heading.getBoundingClientRect().top+frame.getBoundingClientRect().top>=priceBottom+8;
            })()`);
            for(const y of [450,1000,700]) {
                await browser('eval',`window.scrollTo(0,${y})`);
                await browser('wait','--fn',`(() => {
                    const frame=document.querySelector('iframe');
                    const doc=frame?frame.contentDocument:document;
                    const container=doc.getElementById('form-page-container');
                    const bounds=container.getBoundingClientRect();
                    if(bounds.left<12 || bounds.right>doc.documentElement.clientWidth-12)return false;
                    const el=${presentation==='native-embed' ? 'document.querySelector("[data-festapp-embed-price] button")' : 'doc.getElementById("floating-price-widget")'};
                    if(!el || doc.documentElement.scrollWidth>doc.documentElement.clientWidth+1)return false;
                    const rect=el.getBoundingClientRect();
                    const top=rect.top+${presentation==='legacy-embed' ? '(frame?.getBoundingClientRect().top||0)' : '0'};
                    return Math.abs(top-16)<2 && rect.left>=0 && rect.right<=innerWidth+1;
                })()`);
            }
            console.log(`PASS: price position ${presentation} at ${width}px, down and up`);
            await browser('close');
        }
    }
    // Modern website palettes must retain their dark backdrop inside the frame.
    for (const width of [390,1280]) {
        for (const [palette,expected] of [['oklch',[19,33,57]],['p3',[15,52,79]]]) {
            await openBrowser(`${origin}/__price_position_host?native=1&palette=${palette}`);
            await browser('set','viewport',String(width),'844');
            await browser('wait','--fn',`(() => {
                const doc=document.querySelector('iframe')?.contentDocument;
                if(doc?.documentElement.dataset.embedTheme!=='host')return false;
                const computed=doc.defaultView.getComputedStyle(doc.documentElement).backgroundColor;
                const channels=computed.match(/[\\d.]+/g)?.map(Number);
                return channels && ${JSON.stringify(expected)}.every((v,i)=>Math.abs(v-channels[i])<=1)
                    && doc.defaultView.getComputedStyle(doc.getElementById('form-page-container')).color==='rgb(255, 255, 255)'
                    && doc.documentElement.scrollWidth<=doc.documentElement.clientWidth+1;
            })()`);
            console.log(`PASS: inherited ${palette} palette at ${width}px retains a readable backdrop`);
            await browser('close');
        }
    }
    // Account login belongs to the catalogue; public forms stay unbranded.
    await openBrowser(`${origin}/?scenario=guest-login`,()=>browser('wait','--fn',visible('#universal-header')));
    await browser('wait', '--fn', '!document.getElementById("web-client-startup")');
    await browser('click', '.btn-sign-in');
    await browser('wait', '--fn', visible('#google-start'));
    await browser('click', '#google-start');
    await browser('wait', '[data-provider-boundary]');
    await browser('wait', '--fn', 'JSON.parse(sessionStorage.getItem("festapp-google-attempt-v1")).returnPath === "/"');
    console.log('PASS: catalogue login - visible Google action and provider handoff');
} catch (error) {
    console.error('Browser fixture failure:', { phase: browserPhase, requests });
    console.error('Browser session:', await browser('session', 'info').catch(() => null));
    console.error('Browser tabs:', await browser('tab').catch(() => null));
    console.error('Browser errors:', await browser('errors').catch(() => null));
    console.error('Browser snapshot:', await browser('snapshot', '-i').catch(() => null));
    throw error;
} finally {
    await browser('close').catch(() => {});
    await server?.close();
    await rm(temporary, { recursive: true, force: true });
}

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
const execute = promisify(execFile);
const root = path.resolve(import.meta.dirname, '..');
const temporary = await mkdtemp(path.join(tmpdir(), 'festapp-form-access-'));
const config = path.join(temporary, 'browser.json');
await writeFile(config, JSON.stringify({ provider: null, plugins: [], headed: false, autoConnect: false }));
let browserIndex = 0;
let session = `fa-${process.pid}`;
async function browser(...args) {
    const { stdout } = await execute('agent-browser', ['--config', config, '--namespace', session,
        '--session', session, '--headed', 'false', '--allowed-domains', '127.0.0.1', '--json', ...args],
    { timeout: 30000, env: { ...process.env, AGENT_BROWSER_CONFIG: config, AGENT_BROWSER_PLUGINS: '[]', AGENT_BROWSER_DEFAULT_TIMEOUT: '8000' } });
    const result = JSON.parse(stdout);
    assert.equal(result.success, true, result.error);
    return result.data;
}
let server;
try {
    const shell = (await readFile(path.join(root, 'index.html'), 'utf8'))
        .replace('src="/src/main.js"', 'src="/tests/fixtures/form_access/main.js"');
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
            server.middlewares.use(async (req, res, next) => {
                if (req.url.startsWith('/form/account-access') || req.url === '/' || req.url.startsWith('/?')) {
                    res.setHeader('Content-Type', 'text/html'); res.end(shell); return;
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
                    is_open: !scenario.endsWith('closed'), header: '<p>Registration details</p>',
                    fields: [{ id: 1, type: 'email', title: 'E-mail', is_required: true }],
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
    for (const scenario of ['guest-open', 'editor-open', 'editor-closed', 'unit-editor-open', 'unit-editor-closed', 'visitor-closed']) {
        session = `fa-${process.pid}-${++browserIndex}`;
        await browser('open', `${origin}/form/account-access?scenario=${scenario}`);
        assert.equal((await browser('session', 'info')).runtime.pageCount, 1, 'isolated local Chromium required');
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
    // Account login belongs to the catalogue; public forms stay unbranded.
    session = `fa-${process.pid}-${++browserIndex}`;
    await browser('open', `${origin}/?scenario=guest-login`);
    await browser('wait', '--fn', '!document.getElementById("web-client-startup")');
    await browser('wait', '--fn', visible('#universal-header'));
    await browser('click', '.btn-sign-in');
    await browser('wait', '--fn', visible('#google-start'));
    await browser('click', '#google-start');
    await browser('wait', '[data-provider-boundary]');
    await browser('wait', '--fn', 'JSON.parse(sessionStorage.getItem("festapp-google-attempt-v1")).returnPath === "/"');
    console.log('PASS: catalogue login - visible Google action and provider handoff');
} catch (error) {
    console.error('Browser errors:', await browser('errors').catch(() => null));
    console.error('Browser snapshot:', await browser('snapshot', '-i').catch(() => null));
    throw error;
} finally {
    await browser('close').catch(() => {});
    await server?.close();
    await rm(temporary, { recursive: true, force: true });
}

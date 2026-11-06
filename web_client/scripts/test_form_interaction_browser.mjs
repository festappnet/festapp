#!/usr/bin/env node
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createServer} from 'vite';
import {openIsolatedBrowser} from './isolated_browser_startup.mjs';

const execute = promisify(execFile), root = path.resolve(import.meta.dirname, '..');
const temp = await mkdtemp(path.join(tmpdir(), 'form-interaction-'));
const config = path.join(temp, 'browser.json');
await writeFile(config, JSON.stringify({provider:null, plugins:[], headed:false, autoConnect:false, args:'--mute-audio'}));
let server, session, index = 0;
async function browser(...args) {
    const {stdout} = await execute('agent-browser', ['--config', config, '--namespace', session, '--session', session, '--headed', 'false', '--allowed-domains', '127.0.0.1', '--json', ...args], {timeout:30000, env:{...process.env, AGENT_BROWSER_CONFIG:config, AGENT_BROWSER_PLUGINS:'[]'}});
    const result = JSON.parse(stdout); assert.equal(result.success, true, result.error); return result.data;
}
try {
    server = await createServer({root, configFile:false, logLevel:'error', server:{host:'127.0.0.1', port:0}, plugins:[{name:'interaction-fixture', configureServer(s) { s.middlewares.use((req,res,next) => {
        if (req.url !== '/form/test') return next();
        res.setHeader('content-type', 'text/html; charset=utf-8');
        res.end('<!doctype html><html lang="en"><body><main></main><script type="module" src="/tests/fixtures/form_measurement/interaction_host.js"></script></body></html>');
    }); }}]});
    await server.listen();
    await openIsolatedBrowser({open:async()=>{session=`interaction-${process.pid}-${++index}`;await browser('open')}, info:()=>browser('session','info'), close:()=>browser('close')});
    await browser('open', `http://127.0.0.1:${server.httpServer.address().port}/form/test`);
    await browser('wait', '--fn', 'window.fixtureReady');
    const run = async code => (await browser('eval', code)).result;
    const count = () => run("window.sent.filter(x => x.event === 'form_start').length");
    const reset = async options => { await run(`window.resetFixture(${JSON.stringify(options || {})})`); assert.equal(await count(), 0, 'render/restoration must be silent'); };
    await reset({restored:true});
    await run("document.querySelector('input[type=email]').dispatchEvent(new Event('input',{bubbles:true}))");
    assert.equal(await count(), 0, 'synthetic input must be silent');
    await browser('click', 'input[type=email]'); await browser('press', 'Tab');
    assert.equal(await count(), 0, 'empty email blur must be silent');
    await browser('fill', 'input[type=email]', 'a@example.test');
    assert.equal(await count(), 1, 'trusted typing starts form');
    await browser('fill', 'input[type=email]', 'b@example.test');
    assert.equal(await count(), 1, 'form_start is emitted once');
    await reset(); await browser('click', '.btn-add-ticket');
    assert.equal(await count(), 1, 'adding a ticket starts form');
    await reset({restored:true}); await browser('click', '.btn-remove-ticket');
    assert.equal(await count(), 1, 'removing a ticket starts form');
    await reset(); await browser('click', '.btn-clear-selection');
    assert.equal(await count(), 1, 'clearing a default radio selection starts form');
    await reset();
    await run("document.querySelector('input.flatpickr-input')._flatpickr.setDate('2000-01-15', false)");
    assert.equal(await count(), 0, 'restoring a date is silent');
    await browser('click', '.flatpickr-input + input');
    await browser('click', '.flatpickr-day:not(.prevMonthDay):not(.nextMonthDay)');
    assert.equal(await count(), 1, 'choosing a calendar date starts form');
    await reset({consent:false}); await browser('fill', 'input[type=email]', 'before@example.test');
    assert.equal(await count(), 0, 'preconsent interaction is suppressed');
    await run('window.allowed = true'); assert.equal(await count(), 0, 'grant does not replay');
    await browser('fill', 'input[type=email]', 'after@example.test');
    assert.equal(await count(), 1, 'new interaction after grant starts form once');
    console.log('PASS: trusted form interactions, silent initialization/blur/synthetic input, and consent boundary');
} finally {
    if (session) await browser('close').catch(()=>{});
    await server?.close(); await rm(temp, {recursive:true, force:true});
}

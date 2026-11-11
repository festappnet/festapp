#!/usr/bin/env node
import {timed} from './test_timings.mjs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {createServer} from 'vite';
import {createNativeBrowser} from './native_browser.mjs';

const root=path.resolve(import.meta.dirname,'..');
const owner=await createNativeBrowser();let context,page,server;
try {
    server = await createServer({root, configFile:false, logLevel:'error', server:{host:'127.0.0.1', port:0}, plugins:[{name:'interaction-fixture', configureServer(s) { s.middlewares.use((req,res,next) => {
        if (req.url !== '/form/test') return next();
        res.setHeader('content-type', 'text/html; charset=utf-8');
        res.end('<!doctype html><html lang="en"><body><main></main><script type="module" src="/tests/fixtures/form_measurement/interaction_host.js"></script></body></html>');
    }); }}]});
    await timed('browser.server-start', () => server.listen(), {suite: 'form_interaction_browser'});
    const origin=`http://127.0.0.1:${server.httpServer.address().port}`;owner.allow(origin);context=await owner.context();page=await context.newPage();await owner.setTopLevelColorScheme(page,'light');
    await page.goto(`${origin}/form/test`);await page.waitForFunction('window.fixtureReady');
    const run=code=>page.evaluate(code);
    const count = () => run("window.sent.filter(x => x.event === 'form_start').length");
    const reset = async options => { await run(`window.resetFixture(${JSON.stringify(options || {})})`); assert.equal(await count(), 0, 'render/restoration must be silent'); };
    await reset({restored:true});
    await run("document.querySelector('input[type=email]').dispatchEvent(new Event('input',{bubbles:true}))");
    assert.equal(await count(), 0, 'synthetic input must be silent');
    await page.locator('input[type=email]').first().click(); await page.keyboard.press('Tab');
    assert.equal(await count(), 0, 'empty email blur must be silent');
    await page.locator('input[type=email]').first().fill('a@example.test');
    assert.equal(await count(), 1, 'trusted typing starts form');
    await page.locator('input[type=email]').first().fill('b@example.test');
    assert.equal(await count(), 1, 'form_start is emitted once');
    await reset(); await page.locator('.btn-add-ticket').first().click();
    assert.equal(await count(), 1, 'adding a ticket starts form');
    await reset({restored:true}); await page.locator('.btn-remove-ticket').first().click();
    assert.equal(await count(), 1, 'removing a ticket starts form');
    await reset(); await page.locator('.btn-clear-selection').first().click();
    assert.equal(await count(), 1, 'clearing a default radio selection starts form');
    await reset();
    await run("document.querySelector('input.flatpickr-input')._flatpickr.setDate('2000-01-15', false)");
    assert.equal(await count(), 0, 'restoring a date is silent');
    await page.locator('.flatpickr-input + input').first().click();
    await page.locator('.flatpickr-day:not(.prevMonthDay):not(.nextMonthDay)').first().click();
    assert.equal(await count(), 1, 'choosing a calendar date starts form');
    await reset({consent:false}); await page.locator('input[type=email]').first().fill('before@example.test');
    assert.equal(await count(), 0, 'preconsent interaction is suppressed');
    await run('window.allowed = true'); assert.equal(await count(), 0, 'grant does not replay');
    await page.locator('input[type=email]').first().fill('after@example.test');
    assert.equal(await count(), 1, 'new interaction after grant starts form once');
    console.log('PASS: trusted form interactions, silent initialization/blur/synthetic input, and consent boundary');
} finally {
    try { await owner.close(); } finally { await server?.close(); }
}

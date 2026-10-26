#!/usr/bin/env node
// Real browser + real SQL; local transport adapter replaces the Edge/REST gateway.
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import pg from 'pg';
import { createServer } from 'vite';

assert.ok(process.env.SEAT_CHECKOUT_DATABASE_URL, 'Set SEAT_CHECKOUT_DATABASE_URL to the bootstrapped local test database');
const url = new URL(process.env.SEAT_CHECKOUT_DATABASE_URL);
assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'Browser fixtures require a loopback database');
const root = path.resolve(import.meta.dirname, '..');
const temporary = await mkdtemp(path.join(tmpdir(), 'festapp-seat-checkout-'));
const config = path.join(temporary, 'browser.json');
await writeFile(config, JSON.stringify({ provider: null, plugins: [], headed: false, autoConnect: false }));
const session = `seat-checkout-${process.pid}`;
const execute = promisify(execFile);
const db = new pg.Client({ connectionString: url.href });
let server;
let fixture;
let checkout;
const calls = [];
const offlineRecovery = process.argv.includes('--offline-recovery');
async function browser(...args) {
    const { stdout } = await execute('agent-browser', ['--config', config, '--headed', 'false',
        '--session', session, '--allowed-domains', '127.0.0.1', '--json', ...args], { timeout: 30000, env: { ...process.env, AGENT_BROWSER_CONFIG: config, AGENT_BROWSER_PLUGINS: '[]', AGENT_BROWSER_DEFAULT_TIMEOUT: '8000' } });
    const response = JSON.parse(stdout);
    assert.equal(response.success, true, response.error);
    return response.data;
}
try {
    await db.connect();
    const identity = await db.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
    assert.equal(identity.rowCount, 1, 'Require the bootstrap marker of a disposable test database');
    await db.query('BEGIN');
    await db.query("SELECT set_config('festapp.email_wake','scheduled',true), set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claim.role','anon',true)");
    const setup = await db.query(await readFile(path.join(root, 'tests/fixtures/seat_checkout/setup.sql'), 'utf8'));
    fixture = setup.at(-1).rows[0].fixture;
    const rpc = {
        get_form_by_link: ['SELECT public.get_form_by_link($1) AS result', a => [a.form_link]],
        get_blueprint: ['SELECT public.get_blueprint($1,$2,$3) AS result', a => [a.my_secret, a.form_key, a.blueprint_id]],
        select_spot: ['SELECT public.select_spot($1,$2,$3,$4) AS result', a => [a.form_key, a.secret_id, a.spot_id, a.selecting]],
        'send-ticket-order': ['SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) AS result', a => [a.orderDetails, a.commandId, a.clientId]],
    };
    const handleRpc = async (req, res, next) => {
        if (req.url === '/assets/translations/cs.json') {
            res.setHeader('Content-Type', 'application/json');
            res.end(await readFile(path.join(root, '../assets/translations/cs.json')));
            return;
        }
        if (req.url !== '/__seat_checkout_rpc') return next();
        res.setHeader('Content-Type', 'application/json');
        try {
            let body = '';
            for await (const chunk of req) body += chunk;
            const { name, args } = JSON.parse(body);
            assert.ok(Object.hasOwn(rpc, name), `Unexpected RPC ${name}`);
            const [sql, parameters] = rpc[name];
            calls.push(name);
            if (name === 'select_spot') await new Promise(resolve => setTimeout(resolve, 250));
            await db.query('SAVEPOINT browser_rpc');
            await db.query('SET LOCAL ROLE anon');
            const result = (await db.query(sql, parameters(args))).rows[0].result;
            await db.query('RESET ROLE');
            await db.query('RELEASE SAVEPOINT browser_rpc');
            let data = result;
            if (name === 'send-ticket-order') {
                checkout = { payload: args.orderDetails, result: result.data };
                data = result.data.code === 200 ? { code: 200, ticketOrder: result.data } : result.data;
            }
            res.end(JSON.stringify({ data, error: null }));
        } catch (error) {
            await db.query('ROLLBACK TO SAVEPOINT browser_rpc');
            res.end(JSON.stringify({ data: null, error: { message: error.message } }));
        }
    };
    server = await createServer({ root, server: { host: '127.0.0.1', port: 0, strictPort: true }, logLevel: 'error',
        plugins: [{ name: 'seat-checkout-fixture', configureServer(server) { server.middlewares.use(handleRpc); } }] });
    await server.listen();
    const port = server.httpServer.address().port;
    await browser('open', `http://127.0.0.1:${port}/tests/fixtures/seat_checkout/index.html`);
    assert.equal((await browser('session', 'info')).runtime.pageCount, 1, 'Use an isolated local browser');
    await browser('wait', `input[name="${fixture.email}"]`);
    await browser('snapshot', '-i');
    await browser('fill', `input[name="${fixture.email}"]`, 'regression@example.invalid');
    await browser('fill', `input[name="${fixture.name}"]`, 'Test');
    await browser('fill', `input[name="${fixture.surname}"]`, 'Checkout');
    // The reserved .invalid fixture deliberately needs the real email-suffix
    // confirmation. Preserve that confirmation through seat-widget rerenders
    // and the offline recovery below instead of bypassing email validation.
    const suffixWarning = '[data-email-suffix-warning]:not([hidden])';
    await browser('wait', suffixWarning);
    await browser('click', `${suffixWarning} button`);
    await browser('wait', '--fn', '!document.querySelector("[data-email-suffix-warning]:not([hidden])")');
    await browser('click', '.btn-blueprint-select');
    const seatSelector = `.venue-layout-viewer svg g:nth-child(1 of [data-node-id="${fixture.node}"])`;
    await browser('wait', seatSelector);
    const controls = (await browser('eval', `(() => {
        const modal=document.querySelector('.blueprint-modal-container');
        const list=modal.querySelector('.venue-layout-viewer > [role="list"]');
        const bounds=list.getBoundingClientRect();
        const button=modal.querySelector('.blueprint-btn-confirm');
        const b=button.getBoundingClientRect();
        return {listWidth:bounds.width,listHeight:bounds.height,
            buttons:modal.querySelectorAll(':scope > button').length,
            oldClass:button.className,buttonType:button.type,
            centered:Math.abs(b.x+b.width/2-innerWidth/2)<2,
            extraControls:!!modal.querySelector('.blueprint-modal-actions,.blueprint-state-legend')};
    })()`)).result;
    assert.ok(controls.listWidth<=1 && controls.listHeight<=1, 'Assistive seat list must not be visible');
    assert.equal(controls.buttons,1,'Keep the original single Continue button');
    assert.equal(controls.oldClass,'btn btn-primary btn-submit blueprint-btn-confirm');
    assert.equal(controls.buttonType,'button');
    assert.equal(controls.centered,true,'Continue keeps its original centered placement');
    assert.equal(controls.extraControls,false,'No new footer actions or legend');

    await browser('wait', '--fn', "document.querySelector('.blueprint-modal-container').getAnimations().every(a=>a.playState!=='running')");
    const fit=(await browser('eval', "document.querySelector('.venue-layout-viewer svg').getAttribute('viewBox')")).result;
    await browser('click', '.blueprint-zoom-button:first-child');
    assert.notEqual((await browser('eval', "document.querySelector('.venue-layout-viewer svg').getAttribute('viewBox')")).result,fit);
    await browser('click', '.blueprint-zoom-reset');
    const reset = (await browser('eval', "document.querySelector('.venue-layout-viewer svg').getAttribute('viewBox')")).result;
    const fitBounds = fit.trim().split(/\s+/).map(Number);
    const resetBounds = reset.trim().split(/\s+/).map(Number);
    assert.equal(fitBounds.length, 4);
    assert.equal(resetBounds.length, 4);
    // Equivalent fitted bounds can differ by floating-point rounding after zoom.
    resetBounds.forEach((value, index) => assert.ok(
        Number.isFinite(value) && Number.isFinite(fitBounds[index]) && Math.abs(value - fitBounds[index]) < 1e-6,
        `Reset restores fitted viewBox component ${index}: ${value} vs ${fitBounds[index]}`,
    ));
    const viewport="(() => {const s=document.querySelector('.venue-layout-viewer svg'),r=s.getBoundingClientRect();return JSON.stringify({x:r.x,y:r.y,width:r.width,height:r.height,camera:s.getAttribute('viewBox')})})()";
    const beforeClick=(await browser('eval',viewport)).result;
    await browser('snapshot', '-i');
    await browser('click', seatSelector);
    await browser('wait', '--fn', "document.querySelector('.blueprint-btn-confirm').disabled");
    assert.equal((await browser('eval',viewport)).result,beforeClick,'Pending selection must not move or resize the map');
    await browser('wait', '--fn', `document.querySelector('.ticket-item[data-seat-id="${fixture.seat}"]') !== null`);
    // The seat appears optimistically. Wait for the real reservation response
    // before inspecting SQL on the fixture connection used by the RPC adapter.
    await browser('wait', '--fn', "window.__seatCheckoutRpcResults?.has('select_spot') === true");
    assert.equal((await db.query('SELECT secret IS NOT NULL AS reserved FROM eshop.spots WHERE id=$1', [fixture.seat])).rows[0].reserved,
        true, 'The map click must reserve the actual SQL seat');
    assert.equal((await browser('eval',viewport)).result,beforeClick,'Confirmed selection must retain camera and viewport');
    if (offlineRecovery) {
        await browser('set', 'offline', 'on');
        // The selection marker covers the seat group after selection. Dispatch
        // a real pointer gesture at its center, as a buyer would tap it.
        const point = (await browser('eval', `(() => {const r=document.querySelector(${JSON.stringify(seatSelector)}).getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`)).result;
        await browser('mouse', 'move', String(Math.round(point.x)), String(Math.round(point.y)));
        await browser('mouse', 'down');
        await browser('mouse', 'up');
        await browser('wait', '--fn', "!document.querySelector('.blueprint-btn-confirm').disabled");
        // Connectivity returns before checkout. The lost release must not be
        // replayed: a fresh read should confirm the original SQL hold instead.
        await browser('set', 'offline', 'off');
    }
    await browser('click', '.blueprint-btn-confirm');
    await browser('wait', '--fn', '!document.querySelector(".blueprint-modal-container")');
    await browser('snapshot', '-i');
    await browser('scrollintoview', '#dynamic-form .btn-submit');
    await browser('click', '#dynamic-form .btn-submit');
    await browser('wait', '.btn-submit-order');
    await browser('snapshot', '-i');
    await browser('scrollintoview', '.btn-submit-order');
    await browser('wait', '--fn', `(() => { const b=document.querySelector('.btn-submit-order'); const r=b.getBoundingClientRect(); return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('.btn-submit-order')===b && document.getAnimations().every(a=>a.playState!=='running'); })()`);
    await browser('click', '.btn-submit-order');
    await browser('wait', '.result-title');
    assert.equal(checkout?.result.code, 200, `Actual UI payload rejected: ${JSON.stringify(checkout?.result)}`);
    await browser('wait', '.result-title.success-color');
    assert.equal(Number(checkout.payload.ticket[0].spot), fixture.seat);
    assert.ok(calls.includes('select_spot'), 'Seat selection must invoke SQL');
    assert.equal(calls.filter(name => name === 'send-ticket-order').length, 1);
    if (offlineRecovery) {
        assert.equal(calls.filter(name => name === 'select_spot').length, 1, 'Never replay an uncertain release');
        assert.equal(calls.filter(name => name === 'get_blueprint').length, 2, 'Checkout must reread the authoritative hold');
        assert.ok(checkout.payload.fields.some(field => Object.values(field).includes('regression@example.invalid')), 'Keep the entered email');
    }
    const bound = (await db.query(`SELECT x."order" AS order_id, t.state, t.ticket_symbol
        FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
        JOIN eshop.tickets t ON t.id=x.ticket WHERE s.id=$1`, [fixture.seat])).rows[0];
    assert.equal(String(bound.order_id), String(checkout.result.order.id));
    assert.equal(bound.state, 'ordered');
    assert.ok(bound.ticket_symbol);
    console.log('PASS: real map click -> SQL reservation -> preview -> order -> selected seat bound to ticket');
    if (offlineRecovery) console.log('PASS: offline seat release -> reconnect -> authoritative recovery -> one successful order, original seat and answers retained');
} catch (error) {
    console.error('SQL calls:', calls, 'checkout:', checkout?.result?.code);
    console.error('Browser console:', await browser('console').catch(() => null));
    console.error('Browser state:', await browser('get', 'text', 'body').catch(() => null));
    console.error('Browser errors:', await browser('errors').catch(() => null));
    throw error;
} finally {
    try { await browser('close'); } catch {}
    await server?.close();
    try { await db.query('ROLLBACK'); } finally { await db.end(); }
    await rm(temporary, { recursive: true, force: true });
}

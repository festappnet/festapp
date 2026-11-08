import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {pageContext} from '../../src/runtime/page_context.js';
import {installRuntimeState} from '../../src/runtime/runtime_state.js';
import {allowUpdate} from '../../src/runtime/update_policy.js';
import {EmbedChannel} from '../../src/embed/channel.js';
import {envelope, minimumHeight, validMessage} from '../../src/embed/protocol.js';

const source = readFileSync(new URL('../../../web/festapp_update_prompt.js', import.meta.url), 'utf8');
const deferred = () => { let resolve; const promise = new Promise(done => {resolve = done;}); return {promise,resolve}; };
const settle = () => new Promise(resolve => setImmediate(resolve));

for (const path of ['/','/login','/form/a','/form/a/','/form/','/order','/order/']) {
    for (const query of ['', '?embed=1','?embed=true','?embed=0']) {
        test(`page context ${path}${query}`, () => {
            const url = new URL(`https://tickets.invalid${path}${query}`);
            const embedded = ['/form/a','/form/a/','/order'].includes(path) && query === '?embed=1';
            assert.equal(pageContext(url), embedded ? 'public-embed' : 'full-page');
        });
    }
}
test('policy preserves explicit recovery exceptions and rejects unknown operations', () => {
    for (const context of ['public-embed','full-page']) for (const phase of ['starting','ready','failed']) {
        const state = {context,phase};
        assert.equal(allowUpdate('background',state), context !== 'public-embed' || phase !== 'ready');
        for (const reason of ['startup','manual-startup']) assert.equal(allowUpdate(reason,state),phase !== 'ready');
        for (const reason of ['legacy-migration','corrupt-runtime']) assert.equal(allowUpdate(reason,state),true);
        assert.equal(allowUpdate('unrecognized',state),false);
    }
});
test('runtime owns readiness, late failures and concurrent retry/navigation', async () => {
    const win = new EventTarget(); win.Event = Event; win.location = new URL('https://tickets.invalid/form/a?embed=1');
    const state = installRuntimeState(win);
    let readyEvents = 0, preparations = 0, navigations = 0;
    win.addEventListener('festapp-app-ready',() => readyEvents++);
    assert.equal(state.fail('offline'),true); assert.equal(state.phase,'failed');
    const hold = deferred();
    const retry = state.retry(async () => {preparations++; await hold.promise;},() => navigations++);
    assert.equal(await state.retry(() => preparations++,() => navigations++),false);
    state.markReady(); hold.resolve(); await retry;
    assert.equal(state.fail('late-module-error'),false);
    assert.equal(state.markReady(),false);
    assert.equal(readyEvents,1); assert.equal(preparations,1); assert.equal(navigations,0);
    assert.equal(state.navigate('corrupt-runtime',() => navigations++),true);
    assert.equal(state.navigate('legacy-migration',() => navigations++),false);
    assert.equal(navigations,1);
});

// Actual standalone executor with controlled transport responses and a worker handshake.
function boot({embedded = true, ready = false, holdAt, cachedCutover = false} = {}) {
    const hold = deferred(), reached = deferred();
    const messages = [], effects = [], listeners = new Map(), session = new Map();
    const pause = async name => { if (holdAt === name) {reached.resolve(); await hold.promise;} };
    const worker = {state:'activated', postMessage(message, ports = []) {
        messages.push(message);
        if (message.type === 'FESTAPP_QUERY_BUILD_VERSION') {
            Promise.resolve(pause('query')).then(() => ports[0].reply({version:'1'}));
        } else if (message.type === 'FESTAPP_REPAIR_APP_SHELL') {
            Promise.resolve(pause('repair')).then(() => ports[0].reply({ok:true,version:'1'}));
        }
    }};
    const registration = {active:worker, update:() => pause('update'), unregister:async () => effects.push('unregister')};
    const win = {__FESTAPP_BUILD_VERSION__:'1', __FESTAPP_APP_READY__:ready,
        location:{pathname:embedded ? '/form/a' : '/', search:embedded ? '?embed=1' : '',
            href:`https://tickets.invalid/${embedded ? 'form/a?embed=1' : ''}`,
            reload:() => effects.push('reload'),replace:() => effects.push('replace')},
        Event, dispatchEvent() {}, addEventListener:(name,fn) => listeners.set(name,fn),
        setTimeout:() => 1, clearTimeout() {},setInterval() {}};
    if (cachedCutover) session.set('festappCutoverVersion','2');
    const context = {window:win, URL,URLSearchParams,console, navigator:{onLine:true, serviceWorker:{controller:worker,
        getRegistration:async () => {await pause('registration'); return registration;}, getRegistrations:async () => [], addEventListener() {}}},
        MessageChannel:class {constructor() {this.port1={close() {}};this.port2={reply:data => this.port1.onmessage?.({data})};}},
        document:{visibilityState:'visible',addEventListener() {},getElementById:() => null,
            createElement:() => ({style:{},setAttribute(){},addEventListener(){},append(){}}),body:{appendChild:() => effects.push('banner')}},
        sessionStorage:{getItem:key => session.get(key),setItem:(key,value) => session.set(key,value),removeItem:key => session.delete(key)},
        fetch:async () => {await pause('fetch'); return {ok:true,json:async () => ({version:'2'})};}};
    vm.runInNewContext(source,context);
    return {win,hold,reached,effects,messages,listeners,session};
}
for (const holdAt of ['registration','update','query','repair']) {
    test(`ready during ${holdAt} prevents startup cutover and navigation`, async () => {
        const f = boot({holdAt});
        const pending = f.win.cutOverToVersion('1',true,true);
        await f.reached.promise;
        f.win.__FESTAPP_APP_READY__ = true; f.hold.resolve();
        assert.equal(await pending,false);
        assert.deepEqual(f.effects,[]);
        assert.equal(f.session.has('festappCutoverVersion'),false);
    });
}
test('ready during network update and failed-cutover recovery preserves the draft', async () => {
    for (const failed of [false,true]) {
        const f = boot({holdAt:failed ? 'update' : 'fetch'});
        const pending = failed ? f.win.recoverFailedFestappCutover('2',true) : f.listeners.get('focus')();
        await f.reached.promise; f.win.__FESTAPP_APP_READY__ = true; f.hold.resolve();
        await pending; await settle();
        assert.deepEqual(f.effects,[]);
    }
});
test('concurrent cutovers navigate once, full app cutover remains functional', async () => {
    const f = boot({embedded:false,ready:true,holdAt:'update'});
    const first = f.win.cutOverToVersion('1'); await f.reached.promise;
    assert.equal(await f.win.cutOverToVersion('1'),false);
    f.hold.resolve(); assert.equal(await first,true);
    assert.equal(await f.win.cutOverToVersion('1'),false);
    assert.deepEqual(f.effects,['reload']);
});
test('ready embed still answers worker version inquiries', () => {
    const f=boot({ready:true});
    // The service-worker listener is covered in existing update/PWA tests too.
    f.listeners.get('focus')();
    assert.ok(f.messages.some(message => message.type === 'FESTAPP_CLIENT_VERSION'));
    assert.deepEqual(f.effects,[]);
});
test('channel pins valid init only, rejects unknown messages and becomes inert on destroy', () => {
    const peer = {postMessage() {throw Error('closed channel sent data');}};
    const channel = new EmbedChannel({peer:() => peer,destination:'child'});
    const event = (type,fields={}) => ({source:peer,origin:'https://host.invalid',data:envelope(type,'one',fields)});
    assert.equal(channel.receive(event('viewport',{viewportHeight:600})),null);
    assert.equal(channel.receive(event('init',{viewportHeight:239})),null);
    assert.ok(channel.receive(event('init',{viewportHeight:240,extension:'compatible'})));
    assert.equal(channel.receive({...event('init',{viewportHeight:600}),origin:'null'}),null);
    assert.equal(channel.receive(event('unknown')),null);
    channel.destroy(); channel.send('resize',{height:120});
    assert.equal(channel.receive(event('init',{viewportHeight:600})),null);
    assert.equal(minimumHeight(119),240); assert.equal(minimumHeight(120),120); assert.equal(minimumHeight(239),240);
    for (const height of [119,120,239,240,4000,20000,20001]) assert.equal(validMessage(envelope('resize','one',{height}),'host'),height>=120 && height<=20000);
});

test('banner uses the current route context after history changes', () => {
    const f=boot({embedded:false,ready:true});
    f.win.location.pathname='/form/next'; f.win.location.search='?embed=1';
    f.listeners.get('festapp-update-available')({detail:{version:'2'}});
    assert.deepEqual(f.effects,[]);
});

test('local development bypasses recovery registration and network effects', () => {
    const win={__FESTAPP_LOCAL_DEVELOPMENT__:true};
    vm.runInNewContext(source,{window:win});
    assert.equal(win.FestappRuntime,undefined);
    assert.equal(win.recoverFestappStartup,undefined);
});

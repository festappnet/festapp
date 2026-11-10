import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {readHostConsentMode, createHostConsentMode} from '../../src/embed/host_consent_mode.js';
import {measurementProtocol, measurementManifest} from '../../src/components/forms/form_measurement_contract.js';
import {policy} from '../support/measurement_fixture.js';
const denied = {analytics:false, marketing:false};
const granted = {analytics:true, marketing:true};
const command = (...args) => (function () { return arguments; })(...args);
const script = readFileSync(new URL('../../public/embed.js', import.meta.url), 'utf8');

test('ICS is authoritative, update overrides default, only booleans grant', () => {
    const win = {google_tag_data:{ics:{entries:{analytics_storage:{default:true}, ad_storage:{default:true},ad_user_data:{default:true},ad_personalization:{default:true}}}},
        dataLayer:[command('consent','update',{analytics_storage:'denied'})]};
    assert.deepEqual(readHostConsentMode(win), granted);
    win.google_tag_data.ics.entries.analytics_storage.update = false;
    win.google_tag_data.ics.entries.ad_user_data = {default:false};
    assert.deepEqual(readHostConsentMode(win), denied);
    win.google_tag_data.ics.entries.analytics_storage.update = 'granted';
    win.google_tag_data.ics.entries.ad_storage = null;
    assert.deepEqual(readHostConsentMode(win), denied);
});
test('OneTrust ICS without ad_user_data cannot grant marketing', () => {
    const win = {google_tag_data:{ics:{entries:{analytics_storage:{update:true}, ad_storage:{update:true}, ad_user_data:{implicit:true}}}}};
    assert.deepEqual(readHostConsentMode(win), {analytics:true,marketing:false}, 'OneTrust without ad_user_data cannot grant marketing');
    win.google_tag_data.ics.entries.analytics_storage = {implicit:true};
    assert.deepEqual(readHostConsentMode(win), {analytics:false, marketing:false}, 'unset analytics_storage stays denied');
});
test('denied ad_personalization keeps marketing denied (runtime grants all ad purposes together)', () => {
    const ics = {google_tag_data:{ics:{entries:{analytics_storage:{update:true}, ad_storage:{update:true}, ad_user_data:{update:true}, ad_personalization:{update:false}}}}};
    assert.deepEqual(readHostConsentMode(ics), {analytics:true, marketing:false});
    const layer = {dataLayer:[command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'denied'})]};
    assert.deepEqual(readHostConsentMode(layer), {analytics:true, marketing:false});
    layer.dataLayer.push(command('consent','update',{ad_personalization:'granted'}));
    assert.deepEqual(readHostConsentMode(layer), granted);
});
test('a regional default makes that purpose denied until the website CMP updates it', () => {
    const win = {dataLayer:[
        command('consent','default',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'}),
        command('consent','default',{analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied',region:['CZ']})]};
    assert.deepEqual(readHostConsentMode(win), denied, 'global grant plus CZ denial must not grant a Czech visitor');
    win.dataLayer.push(command('consent','update',{analytics_storage:'granted'}));
    assert.deepEqual(readHostConsentMode(win), {analytics:true, marketing:false});
});
test('dataLayer accepts only Arguments and retains partial updates', () => {
    const win = {dataLayer:[]};
    assert.deepEqual(readHostConsentMode(win), denied);
    win.dataLayer.push(command('consent','default',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'}));
    assert.deepEqual(readHostConsentMode(win), granted);
    win.dataLayer.push(command('consent','update',{ad_user_data:'denied'}));
    assert.deepEqual(readHostConsentMode(win), {analytics:true,marketing:false});
    win.dataLayer.push(command('consent','update',{analytics_storage:'denied',ad_user_data:'granted'}));
    win.dataLayer.push(command('consent','default',{analytics_storage:'granted'}));
    assert.deepEqual(readHostConsentMode(win), {analytics:false,marketing:true});
});
test('missing, broken and throwing sources fail closed', () => {
    for (const win of [{}, {dataLayer:{}}, {dataLayer:[null,{},['consent','update',null]]},
        {google_tag_data:{ics:{entries:[]}},dataLayer:[command('consent','update',{analytics_storage:'granted'})]},
        {get google_tag_data() { throw Error('broken'); }}]) assert.deepEqual(readHostConsentMode(win), denied);
});
test('polling notifies only on change, leaves dataLayer untouched and stops without listeners', () => {
    const timers = new Map(); let id = 0;
    const win = {dataLayer:[], setInterval:(callback, delay) => { assert.equal(delay,1000); timers.set(++id,callback); return id; },
        clearInterval:value => timers.delete(value)};
    const source = createHostConsentMode(win);
    let calls = 0;
    const stopA = source.subscribe(() => { calls++; throw Error('listener'); });
    const stopB = source.subscribe(() => calls++);
    assert.equal(timers.size,1);
    const tick = () => [...timers.values()].forEach(callback => callback());
    tick(); assert.equal(calls,0,'no change, no notification');
    win.dataLayer.push(command('consent','update',{analytics_storage:'granted'}));
    tick(); assert.equal(calls,2,'a throwing listener does not stop the others');
    tick(); assert.equal(calls,2);
    assert.deepEqual(source.read(),{analytics:true,marketing:false});
    assert.equal(Object.getOwnPropertyDescriptor(win.dataLayer,'push'),undefined,'host dataLayer stays untouched');
    assert.equal(Object.getOwnPropertyDescriptor(win,'dataLayer').writable,true);
    stopA(); assert.equal(timers.size,1); stopB(); assert.equal(timers.size,0);
});
function host(t, web = false) {
    const dom = new JSDOM(`<iframe data-festapp-embed ${web ? 'data-festapp-datalayer' : ''} src="https://tickets.invalid/form/summer?embed=1"></iframe>`,
        {url:'https://host.invalid',runScripts:'outside-only',pretendToBeVisual:true});
    t.after(() => dom.window.close());
    const win = dom.window, frame = win.document.querySelector('iframe'), sent = [], timers = [];
    win.setInterval = (callback, delay) => { assert.ok([250,1000,20000].includes(delay)); timers.push({callback,delay,active:true}); return timers.length; };
    win.clearInterval = id => { if (timers[id - 1]) { timers[id - 1].active = false; timers[id - 1].callback = () => {}; } };
    const poll = () => timers.filter(timer => timer.active && [250,1000].includes(timer.delay)).forEach(timer => timer.callback());
    frame.contentWindow.postMessage = value => sent.push(value);
    win.eval(script);
    const manifest = measurementManifest({...policy,measurement_consent_bridge:true},'summer');
    const context = (m = manifest) => win.dispatchEvent(new win.MessageEvent('message', {source:frame.contentWindow,origin:'https://tickets.invalid',
        data:{namespace:'festapp-embed',protocol:1,instance:sent[0].instance,type:'measurement-context',measurement:{protocol:measurementProtocol,manifest:m}}}));
    const choice = () => JSON.parse(JSON.stringify(sent.findLast(value => value.type === 'measurement-consent').measurement.consent));
    return {win,frame,sent,context,choice,timers,manifest,poll};
}
test('runtime bridge forwards host consent changes on the next poll', t => {
    const {win,context,choice,poll} = host(t);
    context(); assert.deepEqual(choice(),denied);
    win.dataLayer = [command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];
    poll(); assert.deepEqual(choice(),granted);
    win.dataLayer.push(command('consent','update',{analytics_storage:'denied'}));
    poll(); assert.deepEqual(choice(),{analytics:false,marketing:true});
    win.google_tag_data = {ics:{entries:{analytics_storage:{update:true},ad_storage:{update:false}}}};
    poll(); assert.deepEqual(choice(),{analytics:true,marketing:false});
});
test('explicit setter, Klaro and revision-aware adapter replace the bridge permanently', t => {
    for (const kind of ['setter','klaro','source']) {
        const {win,frame,context,choice,manifest,poll} = host(t);
        context();
        let dispose;
        if (kind === 'setter') win.FestappEmbed.setMeasurementConsent(frame,false);
        if (kind === 'klaro') dispose = win.FestappEmbed.connectKlaro(frame,{consents:{analytics:false,marketing:false},watch(){},unwatch(){}});
        if (kind === 'source') dispose = win.FestappEmbed.connectMeasurementConsent(frame,{
            read:() => ({...denied,processingRevision:manifest.processing_revision}),subscribe:() => () => {}});
        win.dataLayer = [command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];
        poll(); assert.deepEqual(choice(),denied,kind);
        dispose?.(); poll(); assert.deepEqual(choice(),denied,kind);
    }
});
test('website transport never installs the bridge or adopts host consent', t => {
    const {win,context,choice,sent,timers,poll} = host(t,true);
    win.dataLayer = [command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];
    context(); assert.deepEqual(choice(),denied);
    assert.equal(timers.some(timer => timer.delay === 1000),false,'no polling in website mode');
    const count = sent.length; poll(); assert.equal(sent.length,count);
});
test('automatic choice binds to the first manifest revision', t => {
    const {win,context,choice,manifest} = host(t);
    win.dataLayer = [command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];
    context(); assert.deepEqual(choice(),granted);
    context({...manifest,processing_revision:'b'.repeat(64)});
    assert.deepEqual(choice(),denied);
});
test('explicit choices can grant independently of denied Google state, even before context', t => {
    for (const kind of ['setter','klaro','source']) {
        const {win,frame,context,choice,manifest} = host(t);
        if (kind === 'setter') win.FestappEmbed.setMeasurementConsent(frame,granted);
        if (kind === 'klaro') win.FestappEmbed.connectKlaro(frame,{
            confirmed:true,savedConsents:granted,getConsent:() => true,watch(){},unwatch(){}});
        if (kind === 'source') win.FestappEmbed.connectMeasurementConsent(frame,{
            read:() => ({...granted,processingRevision:manifest.processing_revision}),subscribe:() => () => {}});
        context(); assert.deepEqual(choice(),granted,kind);
    }
});
test('live mode switches exclude the automatic source in website mode', async t => {
    const {win,frame,context,choice,sent,poll,timers} = host(t);
    win.dataLayer = [command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];
    context(); assert.deepEqual(choice(),granted);
    frame.setAttribute('data-festapp-datalayer','');
    await new Promise(resolve => setImmediate(resolve));
    context(); assert.deepEqual(choice(),denied);
    assert.equal(timers.filter(timer => timer.active && [250,1000].includes(timer.delay)).length,0);
    const count = sent.length;
    win.dataLayer.push(command('consent','update',{analytics_storage:'denied'}));
    poll(); assert.equal(sent.length,count);
    frame.removeAttribute('data-festapp-datalayer');
    await new Promise(resolve => setImmediate(resolve));
    context(); assert.deepEqual(choice(),{analytics:false,marketing:true});
    assert.equal(timers.filter(timer => timer.active && [250,1000].includes(timer.delay)).length,1);
});

test('plain arrays are ignored as Google ignores them', () => {
    assert.deepEqual(readHostConsentMode({dataLayer:[['consent','update',{
        analytics_storage:'granted', ad_storage:'granted', ad_user_data:'granted', ad_personalization:'granted'}]]}), denied);
});
test('TCF presence blocks marketing while retaining Consent Mode analytics', () => {
    for (const win of [
        {google_tag_data:{ics:{entries:Object.fromEntries(['analytics_storage','ad_storage','ad_user_data','ad_personalization'].map(k => [k,{update:true}]))}}},
        {dataLayer:[command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})]}
    ]) {
        assert.deepEqual(readHostConsentMode(win),granted);
        win.__tcfapi = () => { throw Error('TCF must not be called'); };
        assert.deepEqual(readHostConsentMode(win),{analytics:true,marketing:false});
    }
});
test('incremental fallback reads new entries and resets after shrink or replacement', () => {
    let reads = 0;
    const entry = command('consent','update',{analytics_storage:'granted'});
    const layer = [entry];
    Object.defineProperty(layer,0,{get(){ reads++; return entry; },configurable:true});
    const win = {dataLayer:layer};
    const source = createHostConsentMode(win);
    assert.equal(source.read().analytics,true);
    assert.equal(source.read().analytics,true);
    assert.equal(reads,2,'the second read only checks the last consumed entry, no rescan');
    layer.push(command('consent','update',{analytics_storage:'denied'}));
    assert.deepEqual(source.read(),denied);
    layer.length = 0;
    assert.deepEqual(source.read(),denied);
    win.dataLayer = [command('consent','update',{analytics_storage:'granted'})];
    assert.equal(source.read().analytics,true);
});
test('ICS polls at 250 ms and revocation reaches subscribers on the next tick', () => {
    const timers = new Map(); let id = 0, calls = 0;
    const entries = {analytics_storage:{update:true}};
    const win = {google_tag_data:{ics:{entries}},setInterval:(fn,delay) => {
        assert.equal(delay,250); timers.set(++id,fn); return id;
    },clearInterval:id => timers.delete(id)};
    const source = createHostConsentMode(win), stop = source.subscribe(() => calls++);
    entries.analytics_storage.update = false;
    [...timers.values()][0]();
    assert.equal(calls,1); assert.deepEqual(source.read(),denied);
    stop(); assert.equal(timers.size,0);
});
test('bridge requires Unit opt-in, existing manifests stay denied; explicit adapters still work', t => {
    for (const enabled of [undefined,false]) {
        const {win,frame,context,choice,timers,manifest} = host(t);
        win.dataLayer = [command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})];
        context({...manifest,measurement_consent_bridge:enabled});
        assert.deepEqual(choice(),denied);
        assert.equal(timers.filter(timer => timer.active && [250,1000].includes(timer.delay)).length,0);
        win.FestappEmbed.setMeasurementConsent(frame,granted);
        assert.deepEqual(choice(),granted);
    }
});

test('each missing advertising consent type prevents marketing', () => {
    for (const missing of ['ad_storage','ad_user_data','ad_personalization']) {
        const values = {analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'};
        delete values[missing];
        assert.deepEqual(readHostConsentMode({dataLayer:[command('consent','update',values)]}),{analytics:true,marketing:false},missing);
        const entries = Object.fromEntries(Object.keys(values).map(key => [key,{update:true}]));
        assert.deepEqual(readHostConsentMode({google_tag_data:{ics:{entries}}}),{analytics:true,marketing:false},missing);
    }
});

test('a trimmed dataLayer of unchanged length cannot hide a later revocation', () => {
    const win = {dataLayer:[]};
    for (let i = 0; i < 299; i++) win.dataLayer.push({event:'noise' + i});
    win.dataLayer.push(command('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'}));
    const source = createHostConsentMode(win);
    assert.deepEqual(source.read(), granted);
    win.dataLayer.shift();
    win.dataLayer.push(command('consent','update',{analytics_storage:'denied',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'}));
    assert.equal(win.dataLayer.length, 300);
    assert.deepEqual(source.read(), denied, 'the revocation must not stay behind the cursor');
});

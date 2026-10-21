import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { isEmbed } from '../../src/services/embed_context.js';
import { EmbedBridge, revealEmbedStep } from '../../src/services/embed_bridge.js';

const envelope = (type, instance, values = {}) => ({ namespace: 'festapp-embed', protocol: 1, type, instance, ...values });
const hostScript = readFileSync(new URL('../../public/embed.js', import.meta.url), 'utf8');
function host() {
    const dom = new JSDOM('<iframe data-festapp-embed src="https://tickets.invalid/form/a?embed=1" height="800"></iframe><iframe data-festapp-embed src="https://other.invalid/form/b?embed=1" height="800"></iframe>', { url: 'https://host.invalid', runScripts: 'outside-only', pretendToBeVisual: true });
    const frames = [...dom.window.document.querySelectorAll('iframe')];
    const sent = frames.map(() => []);
    frames.forEach((f, i) => { f.contentWindow.postMessage = (...args) => sent[i].push(args); });
    dom.window.eval(hostScript);
    const message = (frame, origin, data, source = frame.contentWindow) => dom.window.dispatchEvent(new dom.window.MessageEvent('message', { source, origin, data }));
    return { dom, frames, sent, message };
}
test('explicit form URL context only', () => {
    for (const [url, expected] of [['https://t.invalid/form/a?embed=1&preview=true', true], ['https://t.invalid/form/a?embed=true', false], ['https://t.invalid/order?embed=1&order_id=12', true], ['https://t.invalid/admin?embed=1', false], ['https://t.invalid/form/?embed=1', false]]) assert.equal(isEmbed(new URL(url)), expected);
});
test('parent isolates two instances, rejects invalid source/origin/payload, and is idempotent', () => {
    const { dom, frames: [a,b], sent, message } = host();
    const id = sent[0][0][0].instance;
    assert.notEqual(id, sent[1][0][0].instance);
    for (const value of [-1, 0, NaN, Infinity, 20001, '400']) message(a, 'https://tickets.invalid', envelope('resize', id, { height: value }));
    message(a, 'https://evil.invalid', envelope('resize', id, {height: 400}));
    message(a, 'https://tickets.invalid', envelope('resize', id, {height: 400}), b.contentWindow);
    message(a, 'https://tickets.invalid', {...envelope('resize', id, {height: 400}), protocol: 2});
    message(a, 'https://tickets.invalid', envelope('resize', 'other', {height: 400}));
    assert.equal(a.style.height, '');
    message(a, 'https://tickets.invalid', envelope('resize', id, {height: 1240}));
    assert.equal(a.style.height, '1240px'); assert.equal(b.style.height, '');
    dom.window.eval(hostScript);
    const before = sent[0].length;
    message(a, 'https://tickets.invalid', envelope('ready'));
    assert.equal(sent[0].length, before + 1);
    a.dispatchEvent(new dom.window.Event('load'));
    assert.equal(sent[0].at(-1)[0].instance, id);
    dom.window.close();
});
test('child pins parent source, origin and instance, bounds viewport, and disconnects', async () => {
    const dom = new JSDOM('<body><main>Checkout</main></body>', { url: 'https://tickets.invalid/form/a?embed=1', pretendToBeVisual: true });
    const win = dom.window;
    globalThis.document = win.document; globalThis.window = win;
    const sent = []; const parent = {postMessage: (...args) => sent.push(args)};
    Object.defineProperty(win, 'parent', {value: parent});
    let disconnected = false;
    win.ResizeObserver = class { observe() {} disconnect() { disconnected = true; } };
    win.document.body.getBoundingClientRect = () => ({height: 1040});
    const bridge = new EmbedBridge(win); bridge.start();
    assert.deepEqual(sent[0], [{namespace:'festapp-embed',protocol:1,type:'ready'}, '*']);
    const message = (origin, data, source = parent) => win.dispatchEvent(new win.MessageEvent('message', {source,origin,data}));
    message('null', envelope('init','one',{viewportHeight:600}));
    message('https://host.invalid', envelope('init','one',{viewportHeight:600}), {});
    message('https://host.invalid', envelope('init','one',{viewportHeight:NaN}));
    assert.equal(bridge.origin, undefined);
    message('https://host.invalid', envelope('init','one',{viewportHeight:600}));
    await new Promise(resolve => win.requestAnimationFrame(resolve));
    assert.equal(sent.at(-1)[1], 'https://host.invalid');
    assert.equal(sent.at(-1)[0].height, 1040);
    message('https://evil.invalid', envelope('viewport','one',{viewportHeight:900}));
    message('https://host.invalid', envelope('viewport','two',{viewportHeight:900}));
    message('https://host.invalid', envelope('viewport','one',{viewportHeight:4001}));
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-viewport'), '600px');
    message('https://host.invalid', envelope('viewport','one',{viewportHeight:420}));
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-viewport'), '420px');
    const calendar = win.document.createElement('div'); calendar.className = 'flatpickr-calendar';
    calendar.getBoundingClientRect = () => ({bottom:1500});
    win.document.body.append(calendar);
    calendar.classList.add('open');
    await new Promise(resolve => win.requestAnimationFrame(resolve));
    await new Promise(resolve => win.requestAnimationFrame(resolve));
    assert.equal(sent.at(-1)[0].height,1500);
    bridge.destroy(); assert.equal(disconnected, true);
    message('https://host.invalid', envelope('viewport','one',{viewportHeight:700}));
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-viewport'), '420px');
    win.close(); delete globalThis.window; delete globalThis.document;
});

test('parent accepts scrolling only inside its iframe and respects reduced motion', () => {
    const {dom,frames:[frame],sent,message} = host();
    const id = sent[0][0][0].instance;
    Object.defineProperty(frame, 'clientHeight', {value:800});
    const scrolls = [];
    dom.window.scrollTo = value => scrolls.push(value);
    dom.window.matchMedia = () => ({matches:true});
    for (const y of [NaN,Infinity,-1,801,'20']) message(frame, 'https://tickets.invalid', envelope('scroll-request',id,{y}));
    assert.equal(scrolls.length,0);
    message(frame, 'https://tickets.invalid', envelope('scroll-request',id,{y:240}));
    assert.equal(JSON.stringify(scrolls),JSON.stringify([{top:240,behavior:'instant'}]));
    dom.window.close();
});

test('offscreen child still publishes natural height when RAF is suspended', async () => {
    const dom = new JSDOM('<body>Checkout</body>', {url:'https://tickets.invalid/form/a?embed=1'});
    const win = dom.window;
    globalThis.document=win.document; globalThis.window=win;
    const sent=[]; const parent={postMessage:(...args)=>sent.push(args)};
    Object.defineProperty(win,'parent',{value:parent});
    win.ResizeObserver=class {observe(){} disconnect(){}};
    win.requestAnimationFrame=()=>1; win.cancelAnimationFrame=()=>{};
    win.document.body.getBoundingClientRect=()=>({height:1900});
    const bridge=new EmbedBridge(win); bridge.start();
    win.dispatchEvent(new win.MessageEvent('message',{source:parent,origin:'https://host.invalid',data:envelope('init','one',{viewportHeight:600})}));
    await new Promise(resolve=>setTimeout(resolve,230));
    assert.equal(sent.at(-1)[0].height,1900);
    assert.equal(sent.at(-1)[1],'https://host.invalid');
    bridge.destroy(); win.close();delete globalThis.window;delete globalThis.document;
});

test('removing an iframe detaches its load handler', async () => {
    const {dom,frames:[frame],sent}=host();
    const before=sent[0].length;
    frame.remove();
    await new Promise(resolve=>setImmediate(resolve));
    frame.dispatchEvent(new dom.window.Event('load'));
    assert.equal(sent[0].length,before);
    dom.window.close();
});

test('revealing an embed step preserves native keyboard tab stops', () => {
    const dom = new JSDOM('<body><button>Continue</button><section>Result</section></body>', {url:'https://tickets.invalid/form/a?embed=1'});
    globalThis.window=dom.window;globalThis.document=dom.window.document;
    const eventDescriptor=Object.getOwnPropertyDescriptor(globalThis,'CustomEvent');
    globalThis.CustomEvent=dom.window.CustomEvent;
    const button=document.querySelector('button');const section=document.querySelector('section');
    revealEmbedStep(button);assert.equal(button.tabIndex,0);
    revealEmbedStep(section);assert.equal(section.tabIndex,-1);assert.equal(document.activeElement,section);
    dom.window.close();delete globalThis.window;delete globalThis.document;
    if(eventDescriptor)Object.defineProperty(globalThis,'CustomEvent',eventDescriptor);else delete globalThis.CustomEvent;
});

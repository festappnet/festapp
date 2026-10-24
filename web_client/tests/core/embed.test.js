import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { isEmbed } from '../../src/services/embed_context.js';
import { EmbedBridge, revealEmbedStep, preserveCheckoutScroll } from '../../src/services/embed_bridge.js';

const envelope = (type, instance, values = {}) => ({ namespace: 'festapp-embed', protocol: 1, type, instance, ...values });
const hostScript = readFileSync(new URL('../../public/embed.js', import.meta.url), 'utf8');
function host(nativePrice = false) {
    const dom = new JSDOM('<iframe data-festapp-embed src="https://tickets.invalid/form/a?embed=1" height="800"></iframe><iframe data-festapp-embed src="https://other.invalid/form/b?embed=1" height="800"></iframe>', { url: 'https://host.invalid', runScripts: 'outside-only', pretendToBeVisual: true });
    if(nativePrice) dom.window.document.querySelectorAll('iframe').forEach(frame=>{
        const wrapper=dom.window.document.createElement('div');wrapper.dataset.festappEmbedHost='';frame.replaceWith(wrapper);wrapper.append(frame);
    });
    const frames = [...dom.window.document.querySelectorAll('iframe')];
    const sent = frames.map(() => []);
    frames.forEach((f, i) => { f.contentWindow.postMessage = (...args) => sent[i].push(args); });
    dom.window.eval(hostScript);
    const message = (frame, origin, data, source = frame.contentWindow) => dom.window.dispatchEvent(new dom.window.MessageEvent('message', { source, origin, data }));
    return { dom, frames, sent, message };
}
test('explicit form URL context only', () => {
    for (const [url, expected] of [['https://t.invalid/form/a?embed=1&preview=true', true], ['https://t.invalid/form/a?embed=true', false], ['https://t.invalid/admin?embed=1', false], ['https://t.invalid/form/?embed=1', false]]) assert.equal(isEmbed(new URL(url)), expected);
});
test('parent isolates two instances, rejects invalid source/origin/payload, and is idempotent', () => {
    const { dom, frames: [a,b], sent, message } = host();
    const id = sent[0][0][0].instance;
    assert.notEqual(id, sent[1][0][0].instance);
    assert.equal(sent[0][0][0].scrollAlignment, true);
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

test('host appearance is opt-in, resolves stylesheet-relative fonts, updates and preserves fixed height', async () => {
    const {dom, frames: [frame, other], sent, message} = host();
    const style = dom.window.document.createElement('style');
    style.textContent = '@font-face {font-family: "Site Serif"; src:url("fonts/site.woff2"); font-weight:700} body {font-family:"Site Serif", serif;color:rgb(20, 30, 40);background-color:rgb(250, 249, 245)}';
    dom.window.document.head.append(style);
    // jsdom's CSS parser currently drops the @font-face src descriptor.
    const face = style.sheet.cssRules[0].style;
    const property = face.getPropertyValue.bind(face);
    face.getPropertyValue = name => name === 'src' ? 'url("fonts/site.woff2")' : property(name);
    assert.equal(sent[0][0][0].theme, null);
    const navButton=dom.window.document.createElement('button');navButton.style.backgroundColor='transparent';dom.window.document.body.append(navButton);
    frame.dataset.festappStyle = 'inherit'; frame.dataset.festappHeight = 'fixed';
    message(frame, 'https://tickets.invalid', envelope('ready'));
    const theme = sent[0].at(-1)[0].theme;
    assert.equal(theme.fontFamily, '"Site Serif", serif');
    assert.equal(theme.fonts[0].urls[0], 'https://host.invalid/fonts/site.woff2');
    assert.equal(theme.fonts[0].weight, '700');
    assert.equal(theme.primary, 'rgb(20, 30, 40)');
    assert.equal(theme.buttonText, 'rgb(250, 249, 245)');
    assert.equal(sent[1][0][0].theme, null);
    message(frame, 'https://tickets.invalid', envelope('resize', sent[0][0][0].instance, {height:1500}));
    assert.equal(frame.style.height, '');
    delete frame.dataset.festappStyle;
    await new Promise(resolve => dom.window.setTimeout(resolve, 50));
    assert.equal(sent[0].at(-1)[0].theme, null);
    assert.equal(sent[1].at(-1)[0].theme, null);
    assert.equal(other.style.height, '');
    dom.window.close();
});

test('theme requires the pinned parent, rejects CSS/URL injection, cleans fonts and restores service appearance', async () => {
    const dom = new JSDOM('<body><main>Checkout</main></body>', {url:'https://tickets.invalid/form/a?embed=1',pretendToBeVisual:true});
    const win=dom.window;
    globalThis.window=win;globalThis.document=win.document;
    win.CSS={supports:(property,value)=> !value.includes(';') && !value.includes('url(')};
    win.ResizeObserver=class {observe(){} disconnect(){}};
    const fonts=new Set();Object.defineProperty(win.document,'fonts',{value:fonts});
    win.FontFace=class {constructor(family,source,descriptors){Object.assign(this,{family,source,descriptors});} load(){return Promise.resolve(this);}};
    const parent={postMessage(){}};Object.defineProperty(win,'parent',{value:parent});
    const bridge=new EmbedBridge(win);bridge.start();
    const theme={fontFamily:'"Site Serif", serif',text:'rgb(20, 30, 40)',background:'white',primary:'navy',buttonText:'white',fonts:[{family:'Site Serif',urls:['https://host.invalid/fonts/site.woff2'],weight:'100 900',style:'normal',stretch:'normal',unicodeRange:'U+0-10FFFF'}]};
    const message=(type,values,origin='https://host.invalid',source=parent)=>win.dispatchEvent(new win.MessageEvent('message',{source,origin,data:envelope(type,'one',values)}));
    message('theme',{theme});assert.equal(fonts.size,0);
    message('init',{viewportHeight:600,theme},'https://host.invalid',{});assert.equal(fonts.size,0);
    message('init',{viewportHeight:600,theme});assert.equal(fonts.size,1);
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-font-family'),theme.fontFamily);
    message('theme',{theme:{...theme,fontFamily:'evil; background:url(https://evil.invalid)'}});
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-font-family'),theme.fontFamily);
    message('theme',{theme:null},'https://other.invalid');assert.equal(fonts.size,1);
    message('theme',{theme:{...theme,fonts:[{...theme.fonts[0],urls:['javascript:alert(1)']}]}});assert.equal(fonts.size,0);
    message('theme',{theme});message('viewport',{viewportHeight:800,theme});assert.equal(fonts.size,1);
    assert.equal(win.document.body.style.getPropertyValue('--font-family-base'),'');
    message('theme',{theme:null});assert.equal(fonts.size,0);assert.equal(win.document.documentElement.dataset.embedTheme,undefined);
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-font-family'),'');
    bridge.destroy();win.close();delete globalThis.window;delete globalThis.document;
});

test('host scroll immediately reports each iframe visible offset without sending theme data again', async () => {
    const {dom,frames:[a,b],sent}=host();
    a.getBoundingClientRect=()=>({top:-620});b.getBoundingClientRect=()=>({top:250});
    dom.window.dispatchEvent(new dom.window.Event('scroll'));
    assert.equal(sent[0].at(-1)[0].viewportOffset,620, 'scroll must not wait for another animation frame');
    assert.equal(sent[1].at(-1)[0].viewportOffset,0);
    assert.equal(sent[0].at(-1)[0].type,'viewport');
    assert.equal('theme' in sent[0].at(-1)[0],false);
    a.getBoundingClientRect=()=>({top:-40000});
    dom.window.dispatchEvent(new dom.window.Event('scroll'));
    await new Promise(resolve=>dom.window.requestAnimationFrame(resolve));
    assert.equal(sent[0].at(-1)[0].viewportOffset,20000);
    dom.window.close();
});

test('visible viewport offset is bounded and older hosts retain the original fixed position', () => {
    const dom=new JSDOM('<body></body>');
    const bridge=new EmbedBridge(dom.window),style=dom.window.document.documentElement.style;
    bridge.setViewport(600,350);assert.equal(style.getPropertyValue('--embed-visible-top'),'350px');
    for(const value of [-1,20001,NaN,Infinity,'400']) {
        bridge.setViewport(600,value);assert.equal(style.getPropertyValue('--embed-visible-top'),'350px');
    }
    bridge.setViewport(600);assert.equal(style.getPropertyValue('--embed-visible-top'),'0px');
    dom.window.close();
});

test('end-aligned scrolling keeps the final action in view and clamps fixed embeds', () => {
    const {dom,frames:[frame],sent,message}=host();
    Object.defineProperty(frame,'clientHeight',{value:2400,configurable:true});
    Object.defineProperty(dom.window,'innerHeight',{value:600});
    frame.getBoundingClientRect=()=>({top:100});
    const scrolls=[];dom.window.scrollTo=value=>scrolls.push(value);
    dom.window.matchMedia=()=>({matches:true});
    const id=sent[0][0][0].instance;
    message(frame,'https://tickets.invalid',envelope('scroll-request',id,{y:2100,block:'end'}));
    assert.equal(scrolls.at(-1).top,1600);
    Object.defineProperty(frame,'clientHeight',{value:800});
    message(frame,'https://tickets.invalid',envelope('scroll-request',id,{y:2100,block:'end'}));
    assert.equal(scrolls.at(-1).top,300);
    const before=scrolls.length;
    message(frame,'https://tickets.invalid',envelope('scroll-request',id,{y:20001,block:'end'}));
    message(frame,'https://tickets.invalid',envelope('scroll-request',id,{y:20,block:'invalid'}));
    assert.equal(scrolls.length,before);
    dom.window.close();
});

test('automatic child publishes height and delegates scrolling without native ancestor scrolling', () => {
    const dom=new JSDOM('<body><button>Submit</button></body>');
    const win=dom.window,requests=[],native=[];
    win.document.body.getBoundingClientRect=()=>({height:1200});
    const button=win.document.querySelector('button');
    button.getBoundingClientRect=()=>({top:1000,bottom:1080});
    button.scrollIntoView=value=>native.push(value);
    win.matchMedia=()=>({matches:true});
    Object.defineProperty(win,'parent',{value:{postMessage:data=>requests.push(data)}});
    const bridge=new EmbedBridge(win);bridge.origin='https://host.invalid';bridge.instance='one';bridge.scrollAlignment=true;
    bridge.scrollTo(button,{block:'end'});
    assert.equal(requests[0].type,'resize');assert.equal(requests[0].height,1200);
    assert.equal(requests[1].type,'scroll-request');assert.equal(requests[1].y,1080);assert.equal(requests[1].block,'end');
    assert.deepEqual(native,[], 'scrollIntoView would also scroll the host and race its message handler');
    dom.window.close();
});

test('nearest host scroll leaves visible controls alone and reveals only an offscreen target', () => {
    const {dom,frames:[frame],sent,message}=host();
    const win=dom.window, scrolls=[];
    Object.defineProperty(frame,'clientHeight',{value:1800});
    Object.defineProperty(win,'innerHeight',{value:600});
    frame.getBoundingClientRect=()=>({top:-200});
    win.scrollTo=value=>scrolls.push(value);
    win.matchMedia=()=>({matches:true});
    const id=sent[0][0][0].instance;
    const request=(y,height)=>message(frame,'https://tickets.invalid',envelope('scroll-request',id,{y,height,block:'nearest'}));
    request(300,80);
    assert.equal(scrolls.length,0,'a fully visible target must not move the page');
    request(900,80);
    assert.equal(scrolls.at(-1).top,196,'reveal just the obscured bottom with a 16px reading gap');
    scrolls.length=0;
    request(0,80);
    assert.equal(scrolls.at(-1).top,0,'never scroll above the document');
    const before=scrolls.length;
    for(const height of [-1,NaN,Infinity,'80',20001]) request(300,height);
    assert.equal(scrolls.length,before,'invalid target sizes cannot move the host');
    dom.window.close();
});

test('fixed children coordinate local and host visibility; helper-free children use only native scrolling', () => {
    for(const managed of [false,true]) {
        const dom=new JSDOM('<body><button>Continue</button></body>',{pretendToBeVisual:true});
        const win=dom.window,requests=[],positions=[];
        Object.defineProperty(win,'innerHeight',{value:800});
        Object.defineProperty(win,'parent',{value:{postMessage:data=>requests.push(data)}});
        win.scrollTo=value=>positions.push(value);
        win.matchMedia=()=>({matches:true});
        win.document.body.getBoundingClientRect=()=>({height:1800});
        const button=win.document.querySelector('button');
        button.getBoundingClientRect=()=>({top:1400,bottom:1480,height:80});
        const native=[];
        button.scrollIntoView=value=>native.push(value);
        const bridge=new EmbedBridge(win);
        if(managed) {bridge.origin='https://host.invalid';bridge.instance='fixed';bridge.autoHeight=false;bridge.scrollAlignment=true;}
        bridge.scrollTo(button,{block:'nearest'});
        if(managed) {
            assert.equal(native.length,0);
            assert.equal(positions.length,1);
            assert.equal(positions[0].top,696);
            const request=requests.find(data=>data.type==='scroll-request');
            assert.equal(request.block,'nearest');
            assert.equal(request.y,704);
        } else {
            assert.equal(requests.length,0);
            assert.equal(positions.length,0);
            assert.deepEqual(native,[{block:'nearest',behavior:'instant'}]);
        }
        dom.window.close();
    }
});

test('native price projection keeps the iframe intact, renders text safely, and does not track page scrolling', () => {
    const {dom,frames:[frame],sent,message}=host(true);
    const source=frame.contentWindow,id=sent[0][0][0].instance;
    const data={price:{count:2,total:'240 CZK',lines:['<script>text only</script>']},appearance:{color:'white','background-color':'black'},visible:true};
    message(frame,'https://evil.invalid',envelope('price',id,data));
    assert.equal(dom.window.document.querySelector('[data-festapp-embed-price]'),null);
    message(frame,'https://tickets.invalid',envelope('price',id,data));
    const layer=dom.window.document.querySelector('[data-festapp-embed-price]');
    assert.equal(layer.hidden,false);assert.match(layer.textContent,/2x.*240 CZK/);
    assert.equal(layer.querySelector('script'),null);assert.match(layer.textContent,/<script>/);
    assert.equal(frame.contentWindow,source,'projecting price must never move or reload the iframe');
    assert.equal(layer.querySelector('button').style.position,'sticky');
    const before=sent[0].length;
    dom.window.dispatchEvent(new dom.window.Event('scroll'));
    assert.equal(sent[0].length,before,'native sticky price needs no cross-frame scroll update');
    layer.querySelector('button').click();assert.equal(sent[0].at(-1)[0].type,'price-activate');
    message(frame,'https://tickets.invalid',envelope('price',id,{price:null,visible:false}));
    assert.equal(layer.hidden,true);
    dom.window.close();
});

test('host restores only a saved scroll snapshot belonging to the same iframe', () => {
    const {dom,frames:[a,b],sent,message}=host();
    Object.defineProperty(dom.window,'scrollY',{value:620,writable:true});
    const positions=[];dom.window.scrollTo=value=>positions.push(value);
    const id=sent[0][0][0].instance;
    message(a,'https://tickets.invalid',envelope('scroll-save',id,{snapshot:'saved'}));
    dom.window.scrollY=1200;
    message(b,'https://other.invalid',envelope('scroll-restore',sent[1][0][0].instance,{snapshot:'saved'}));
    assert.equal(positions.length,0);
    message(a,'https://tickets.invalid',envelope('scroll-restore',id,{snapshot:'saved'}));
    assert.equal(positions[0].top,620);assert.equal(positions[0].behavior,'instant');
    message(a,'https://tickets.invalid',envelope('scroll-restore',id,{snapshot:'saved'}));
    assert.equal(positions.length,1,'a snapshot is restored once');dom.window.close();
});

test('overlay restoration preserves standalone scroll and history policy without revealing a new step', () => {
    const dom=new JSDOM('<body></body>',{url:'https://tickets.invalid/form/a'}),win=dom.window;
    Object.defineProperty(win,'scrollY',{value:400,writable:true});
    win.history.scrollRestoration='auto';const positions=[];
    win.scrollTo=value=>positions.push(value);
    const restore=preserveCheckoutScroll(win);
    assert.equal(win.history.scrollRestoration,'manual');
    win.scrollY=900;restore();restore();
    assert.equal(positions.length,1);assert.equal(positions[0].top,400);
    assert.equal(win.history.scrollRestoration,'auto');dom.window.close();
});

test('submitting discards a snapshot without scrolling and cannot restore it later', () => {
    const {dom,frames:[frame],sent,message}=host();
    const positions=[];
    dom.window.scrollTo=value=>positions.push(value);
    const id=sent[0][0][0].instance;
    message(frame,'https://tickets.invalid',envelope('scroll-save',id,{snapshot:'submitted'}));
    message(frame,'https://evil.invalid',envelope('scroll-discard',id,{snapshot:'submitted'}));
    message(frame,'https://tickets.invalid',envelope('scroll-discard',id,{snapshot:'submitted'}));
    message(frame,'https://tickets.invalid',envelope('scroll-restore',id,{snapshot:'submitted'}));
    assert.equal(positions.length,0);
    dom.window.close();
});

// Legacy protocol 1 hosts send viewportHeight only and treat every y as start.
test('new child uses one native reveal with a legacy host for end and nearest alignment', () => {
    for (const block of ['end', 'nearest']) {
        const dom = new JSDOM('<body><button>Submit</button></body>');
        const win = dom.window, requests = [], native = [];
        Object.defineProperty(win, 'parent', {value: {postMessage: data => requests.push(data)}});
        win.matchMedia = () => ({matches: true});
        win.document.body.getBoundingClientRect = () => ({height: 1800});
        const button = win.document.querySelector('button');
        button.getBoundingClientRect = () => ({top: 1400, bottom: 1480, height: 80});
        button.scrollIntoView = options => native.push(options);
        const bridge = new EmbedBridge(win);
        bridge.origin = 'https://host.invalid'; bridge.instance = 'legacy';
        bridge.scrollTo(button, {block});
        assert.deepEqual(native, [{block, behavior: 'instant'}]);
        assert.equal(requests.filter(message => message.type === 'scroll-request').length, 0);
        assert.equal(requests[0].type, 'resize');
        dom.window.close();
    }
});

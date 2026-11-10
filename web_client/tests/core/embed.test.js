import {measurementProtocol} from '../../src/components/forms/form_measurement_contract.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { FormModel } from '../../src/components/forms/form_models.js';
import { isEmbed } from '../../src/services/embed_context.js';
import { EmbedBridge, revealEmbedStep, preserveCheckoutScroll } from '../../src/services/embed_bridge.js';

const envelope = (type, instance, values = {}) => ({ namespace: 'festapp-embed', protocol: 1, type, instance, ...values });
const hostScript = readFileSync(new URL('../../public/embed.js', import.meta.url), 'utf8');
function host(nativePrice = false, configure = () => {}) {
    const dom = new JSDOM('<iframe data-festapp-embed src="https://tickets.invalid/form/a?embed=1" height="800"></iframe><iframe data-festapp-embed src="https://other.invalid/form/b?embed=1" height="800"></iframe>', { url: 'https://host.invalid', runScripts: 'outside-only', pretendToBeVisual: true });
    if(nativePrice) dom.window.document.querySelectorAll('iframe').forEach(frame=>{
        const wrapper=dom.window.document.createElement('div');wrapper.dataset.festappEmbedHost='';frame.replaceWith(wrapper);wrapper.append(frame);
    });
    const frames = [...dom.window.document.querySelectorAll('iframe')];
    const sent = frames.map(() => []);
    frames.forEach((f, i) => { f.contentWindow.postMessage = (...args) => sent[i].push(args); });
    configure(dom.window);
    dom.window.eval(hostScript);
    const message = (frame, origin, data, source = frame.contentWindow) => dom.window.dispatchEvent(new dom.window.MessageEvent('message', { source, origin, data }));
    return { dom, frames, sent, message };
}
test('explicit form URL context only', () => {
    for (const [url, expected] of [['https://t.invalid/form/a?embed=1&preview=true', true], ['https://t.invalid/form/a?embed=true', false], ['https://t.invalid/admin?embed=1', false], ['https://t.invalid/form/?embed=1', false]]) assert.equal(isEmbed(new URL(url)), expected);
});
test('parent matches the default iframe canvas to the host before starting the child handshake', t => {
    const {dom,frames,sent}=host();
    t.after(()=>dom.window.close());
    for(const [index,frame] of frames.entries()) {
        assert.equal(frame.style.colorScheme,'light');
        assert.equal(sent[index][0][0].theme.colorScheme,'light');
        assert.equal(sent[index][0][0].type,'init');
    }
});
test('parent exports an explicitly declared host scheme', t => {
    const {dom,frames}=host(false,win=>{
        const frames=win.document.querySelectorAll('iframe');
        for (const [index,frame] of [...frames].entries()) {
            const wrapper=win.document.createElement('section');
            wrapper.style.colorScheme=index===0?'light':'dark';
            frame.replaceWith(wrapper); wrapper.append(frame);
        }
    });
    t.after(()=>dom.window.close());
    assert.equal(frames[0].style.colorScheme,'light');
    assert.equal(frames[1].style.colorScheme,'dark');
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
    assert.equal(a.style.height, '120px');
    message(a, 'https://tickets.invalid', envelope('resize', id, {height: 1240}));
    assert.equal(a.style.height, '1240px'); assert.equal(b.style.height, '120px');
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

test('host supplies appearance and explicit mode independently of fixed height', async () => {
    const {dom, frames: [frame, other], sent, message} = host();
    const style = dom.window.document.createElement('style');
    style.textContent = '@font-face {font-family: "Site Serif"; src:url("fonts/site.woff2"); font-weight:700} body {font-family:"Site Serif", serif;color:rgb(20, 30, 40);background-color:rgb(250, 249, 245)}';
    dom.window.document.head.append(style);
    // jsdom's CSS parser currently drops the @font-face src descriptor.
    const face = style.sheet.cssRules[0].style;
    const property = face.getPropertyValue.bind(face);
    face.getPropertyValue = name => name === 'src' ? 'url("fonts/site.woff2")' : property(name);
    assert.ok(sent[0][0][0].theme);
    const navButton=dom.window.document.createElement('button');navButton.style.backgroundColor='transparent';dom.window.document.body.append(navButton);
    frame.dataset.festappStyle = 'inherit'; frame.dataset.festappHeight = 'fixed';
    message(frame, 'https://tickets.invalid', envelope('ready'));
    assert.equal(Object.hasOwn(sent[0].at(-1)[0], 'inheritStyle'), false);
    assert.equal(sent[0].at(-1)[0].styleMode,undefined);
    const theme = sent[0].at(-1)[0].theme;
    assert.equal(theme.fontFamily, '"Site Serif", serif');
    assert.equal(theme.fonts[0].urls[0], 'https://host.invalid/fonts/site.woff2');
    assert.equal(theme.fonts[0].weight, '700');
    assert.equal(theme.primary, 'rgb(20, 30, 40)');
    assert.equal(theme.buttonText, 'rgb(250, 249, 245)');
    assert.ok(sent[1][0][0].theme);
    message(frame, 'https://tickets.invalid', envelope('resize', sent[0][0][0].instance, {height:1500}));
    assert.equal(frame.style.height, '120px');
    frame.dataset.festappStyle = 'default';
    message(frame, 'https://tickets.invalid', envelope('ready'));
    assert.equal(Object.hasOwn(sent[0].at(-1)[0], 'inheritStyle'), false);
    assert.equal(sent[0].at(-1)[0].styleMode,undefined);
    delete frame.dataset.festappStyle;
    await new Promise(resolve => dom.window.setTimeout(resolve, 50));
    assert.equal(sent[0].at(-1)[0].styleMode,undefined);
    assert.equal(sent[0].findLast(([data])=>data.theme)?.[0].theme.fontFamily, theme.fontFamily);
    assert.ok(sent[1].at(-1)[0].theme);
    assert.equal(other.style.height, '120px');
    dom.window.close();
});

test('host appearance never derives website colors from a projected checkout price', () => {
    const {dom,frames:[frame,other],sent,message}=host(true);
    const button=dom.window.document.createElement('button');
    button.style.cssText='background-color:rgb(10, 20, 30);color:white';
    dom.window.document.body.append(button);
    const id=sent[0][0][0].instance;
    message(frame,'https://tickets.invalid',envelope('price',id,{
        price:{count:1,total:'100 Kč',lines:[]},visible:true,
        appearance:{'background-color':'rgb(200, 0, 0)',color:'white'}
    }));
    for(const [index,target,origin] of [[0,frame,'https://tickets.invalid'],[1,other,'https://other.invalid']]) {
        message(target,origin,envelope('ready'));
        assert.equal(sent[index].at(-1)[0].theme.primary,'rgb(10, 20, 30)',
            'checkout projections cannot become website appearance sources');
    }
    dom.window.close();
});

test('host theme skips transparent white ancestors and unpainted button colors', () => {
    const dom = new JSDOM('<body><section><iframe data-festapp-embed src="https://tickets.invalid/form/a?embed=1"></iframe></section></body>',
        {url:'https://host.invalid', runScripts:'outside-only', pretendToBeVisual:true});
    const document = dom.window.document;
    const frame = document.querySelector('iframe');
    const section = document.querySelector('section');
    const sent = [];
    frame.contentWindow.postMessage = (...args) => sent.push(args);
    dom.window.eval(hostScript);
    document.body.style.cssText = 'color:rgb(0, 0, 0);background-color:rgb(255, 255, 255)';
    section.style.backgroundColor = 'rgba(255, 255, 255, 0)';
    frame.dataset.festappStyle = 'inherit';
    const theme = () => {
        dom.window.dispatchEvent(new dom.window.MessageEvent('message',
            {source:frame.contentWindow, origin:'https://tickets.invalid', data:envelope('ready')}));
        return sent.at(-1)[0].theme;
    };
    assert.equal(theme().background, 'rgb(255, 255, 255)');
    assert.equal(theme().buttonText, 'rgb(255, 255, 255)');
    // An opaque color with a zero blue channel must not be mistaken for alpha 0.
    section.style.backgroundColor = 'rgb(255, 255, 0)';
    assert.equal(theme().buttonText, 'rgb(255, 255, 0)');
    const button = document.createElement('button');
    button.style.cssText = 'background-color:navy;color:white;opacity:0';
    section.append(button);
    assert.equal(theme().primary, 'rgb(0, 0, 0)');
    button.style.opacity = '1'; button.style.color = 'rgba(255, 255, 255, 0)';
    assert.equal(theme().primary, 'rgb(0, 0, 0)');
    button.style.color = 'white';
    assert.equal(theme().primary, 'rgb(0, 0, 128)');
    assert.equal(theme().buttonText, 'rgb(255, 255, 255)');
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
    message('init',{viewportHeight:600,theme});assert.equal(fonts.size,0);
    // Loading saved form data enables the already received host presentation.
    bridge.setInheritStyle(new FormModel({data:{design:{embed_inherit_style:true}}}).embedInheritStyle);assert.equal(fonts.size,1);
    bridge.setInheritStyle(new FormModel({data:{design:{embed_inherit_style:false}}}).embedInheritStyle);assert.equal(fonts.size,0);
    message('theme',{theme});assert.equal(fonts.size,0);
    assert.equal(win.document.documentElement.dataset.embedTheme,undefined);
    bridge.setInheritStyle(new FormModel({data:{design:{embed_inherit_style:true}}}).embedInheritStyle);assert.equal(fonts.size,1);
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-font-family'),theme.fontFamily);
    message('theme',{theme:{...theme,fontFamily:'evil; background:url(https://evil.invalid)'}});
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-font-family'),theme.fontFamily);
    bridge.setInheritStyle(false);
    bridge.setInheritStyle(true);
    assert.equal(win.document.documentElement.style.getPropertyValue('--embed-font-family'),theme.fontFamily,
        'invalid host input must not poison the last valid presentation');
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

const measurement={measurement_protocol:measurementProtocol,organization:1,unit:2,form_link:'summer',processing_revision:'a',runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing']};
const plain=value=>JSON.parse(JSON.stringify(value));
function measurementHost() {
 const f=host(),{dom,frames:[frame],sent,message}=f;
 Object.defineProperty(dom.window.document,'hidden',{value:false,configurable:true});
 frame.setAttribute('data-festapp-datalayer','');const instance=sent[0][0][0].instance;
 const send=(type,values={},origin='https://tickets.invalid',source=frame.contentWindow)=>message(frame,origin,envelope(type,instance,values),source);
 send('measurement-context',{measurement:{protocol:measurementProtocol,manifest:measurement}});
 return {...f,frame,instance,send,last:()=>sent[0].at(-1)[0]};
}
test('a helper alone measures: lease without a CMP, setters and Klaro only pass the choice on',()=>{
 const f=measurementHost();const {dom,frame,send,last}=f;let watcher;
 const leaseId=last().measurement.leaseId;assert.ok(leaseId,'no CMP is needed for a lease');
 assert.deepEqual(plain(last().measurement.consent),{analytics:false,marketing:false});
 send('analytics',{payload:{event:'page_view'}});assert.equal(dom.window.dataLayer,undefined,'protocol 1 event stays rejected');
 dom.window.FestappEmbed.setMeasurementConsent(frame,{analytics:true,marketing:true});
 assert.deepEqual(plain(last().measurement.consent),{analytics:true,marketing:true});assert.equal(last().measurement.leaseId,leaseId);
 dom.window.FestappEmbed.setMeasurementConsent(frame,false);
 assert.deepEqual(plain(last().measurement.consent),{analytics:false,marketing:false});assert.equal(last().measurement.leaseId,leaseId,'refusal keeps measuring');
 const manager={confirmed:true,savedConsents:{analytics:true,marketing:true},getConsent:()=>true,watch:w=>watcher=w,unwatch(){}};
 const stop=dom.window.FestappEmbed.connectKlaro(frame,manager);watcher.update();
 assert.deepEqual(plain(last().measurement.consent),{analytics:true,marketing:true});stop();dom.window.close();
});
test('lease binds instance and generation; a revoked choice does not stop host events',()=>{
 const f=measurementHost(),{dom,frame,send,last}=f;let choice={processingRevision:'a',analytics:true,marketing:true},notify;
 const source={read:context=>{assert.equal(context.processingRevision,'a');return choice;},subscribe:fn=>{notify=fn;return ()=>{};}};
 const disconnect=dom.window.FestappEmbed.connectMeasurementConsent(frame,source);const leaseId=last().measurement.leaseId;assert.ok(leaseId);
 const measurementEnvelope=()=>({protocol:measurementProtocol,manifest:measurement,generation:7,leaseId});
 const emit=(m=measurementEnvelope(),origin,source)=>send('analytics',{measurement:m,payload:{event:'page_view'}},origin,source);
 emit();assert.equal(dom.window.dataLayer,undefined,'activate handshake required');
 send('measurement-activate',{measurement:measurementEnvelope()});emit();assert.equal(dom.window.dataLayer.filter(p=>p.event).length,1);
 emit({...measurementEnvelope(),generation:6});emit({...measurementEnvelope(),leaseId:'stale'});emit(measurementEnvelope(),'https://evil.invalid');emit(measurementEnvelope(),undefined,{});
 assert.equal(dom.window.dataLayer.filter(p=>p.event).length,1);
 choice=null;notify();assert.equal(last().measurement.leaseId,leaseId);assert.deepEqual(plain(last().measurement.consent),{analytics:false,marketing:false});
 emit();assert.equal(dom.window.dataLayer.filter(p=>p.event).length,2,'consent state never gates the event');
 choice={...choice,processingRevision:'b'};
 disconnect();emit();assert.equal(dom.window.dataLayer.filter(p=>p.event).length,3);dom.window.close();
});
test('unreadable, partial or stale-revision source keeps the lease and reports the real choice',()=>{
 for(const [choice,consent] of [[null,{analytics:false,marketing:false}],[{processingRevision:'a',analytics:true},{analytics:true,marketing:false}],[{processingRevision:'b',analytics:true,marketing:true},{analytics:false,marketing:false}]]){
  const f=measurementHost();const disconnect=f.dom.window.FestappEmbed.connectMeasurementConsent(f.frame,{read:()=>choice,subscribe:()=>()=>{}});
  assert.ok(f.last().measurement.leaseId);assert.deepEqual(plain(f.last().measurement.consent),consent);disconnect();f.dom.window.close();
 }
});
test('host dataLayer receives the contact only on conversions and clears it afterwards',()=>{
 const f=measurementHost();
 const m={protocol:measurementProtocol,manifest:measurement,generation:1,leaseId:f.last().measurement.leaseId};f.send('measurement-activate',{measurement:m});
 f.send('analytics',{measurement:m,payload:{event:'generate_lead',event_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',currency:'CZK',value:0,lead_source:'waitlist',user_data:{email:'buyer@example.test',phone_number:'+420601234567',first_name:'PRIVATE'}}});
 f.send('analytics',{measurement:m,payload:{event:'page_view',user_data:{email:'buyer2@example.test'}}});
 const layer=f.dom.window.dataLayer;
 assert.deepEqual(plain(layer.find(p=>p.event==='generate_lead').user_data),{email:'buyer@example.test',phone_number:'+420601234567'});
 assert.equal(layer.find(p=>p.event==='form_page_view').user_data,undefined);
 assert.deepEqual(plain(layer[layer.findIndex(p=>p.event==='generate_lead')+1]),{user_data:null,form_embedded:false});assert.doesNotMatch(JSON.stringify(layer),/PRIVATE|buyer2/);f.dom.window.close();
});

function child(){
 const dom=new JSDOM('<body></body>',{url:'https://tickets.invalid/form/a?embed=1',pretendToBeVisual:true});
 const win=dom.window;globalThis.document=win.document;globalThis.window=win;
 const sent=[],calls=[];const parent={postMessage:(...args)=>sent.push(args)};
 Object.defineProperty(win,'parent',{value:parent});win.ResizeObserver=class{observe(){}disconnect(){}};
 const bridge=new EmbedBridge(win);bridge.start();
 const runtime={setConsent:value=>calls.push(value),start:()=>calls.push('start'),stop:()=>calls.push('stop'),revokeMeasurement(){},measurementAllowed:()=>false,track:()=>false};
 bridge.setMeasurementRuntime(runtime);
 const init=(data={},source=parent,origin='https://host.invalid')=>win.dispatchEvent(new win.MessageEvent('message',{source,origin,data:envelope('init','one',{viewportHeight:600,...data})}));
 return{dom,win,sent,calls,bridge,init,done(){bridge.destroy();dom.window.close();delete globalThis.window;delete globalThis.document;}};
}

test('layout handshake, legacy consent and absent helper never start Unit code',async()=>{
 const f=child();f.init({consent:{analytics:true,marketing:true}});assert.equal(f.calls.includes('start'),false);assert.equal(f.bridge.selection(),null);
 f.init({measurementProtocol,dataLayer:true});assert.equal(f.bridge.selection(),'host');assert.equal(f.bridge.track({event:'page_view'}),false);
 f.done();
 const absent=child();assert.equal(absent.bridge.selection(),null);assert.equal(absent.calls.includes('start'),false);absent.done();
});

test('host refreshes changed appearance while scroll messages omit presentation', async () => {
    const {dom, sent} = host();
    const win = dom.window;
    try {
        win.document.body.style.backgroundColor = 'rgb(10, 20, 30)';
        await new Promise(resolve => win.setTimeout(resolve, 50));
        const updates = () => sent[0].filter(([data]) => data.type === 'theme');
        assert.equal(updates().at(-1)[0].theme.background, 'rgb(10, 20, 30)');
        const count = updates().length;
        win.document.body.style.border = '1px solid black';
        await new Promise(resolve => win.setTimeout(resolve, 50));
        assert.equal(updates().length, count, 'unrelated mutations do not resend appearance');
        win.dispatchEvent(new win.Event('scroll'));
        const [viewport] = sent[0].at(-1);
        assert.equal(viewport.type, 'viewport');
        assert.equal(Object.hasOwn(viewport, 'theme'), false);
    } finally { win.close(); }
});

test('host preset and sampled button always export a readable CTA pair', () => {
    const {dom, frames:[frame], sent, message} = host();
    dom.window.document.body.style.cssText = '--wp--preset--color--primary:#ffffcc;background:white;color:black';
    const button = dom.window.document.createElement('button');
    button.style.cssText = 'background:navy;color:white';
    dom.window.document.body.append(button);
    message(frame, 'https://tickets.invalid', envelope('ready'));
    let theme = sent[0].at(-1)[0].theme;
    assert.equal(theme.primary, 'rgb(255, 255, 204)');
    assert.equal(theme.buttonText, 'rgb(0, 0, 0)');
    dom.window.document.body.style.setProperty('--wp--preset--color--primary', '#112233');
    button.style.cssText = 'background:white;color:black';
    message(frame, 'https://tickets.invalid', envelope('ready'));
    theme = sent[0].at(-1)[0].theme;
    assert.equal(theme.primary, 'rgb(17, 34, 51)');
    assert.equal(theme.buttonText, 'rgb(255, 255, 255)');
    dom.window.close();
});

test('host skips hidden and outline candidates to find a painted website button', () => {
    const {dom, frames:[frame], sent, message} = host();
    const candidates = dom.window.document.createElement('div');
    candidates.innerHTML = '<button style="display:none;background:red;color:white">Hidden</button>' +
        '<div style="opacity:0"><button style="background:red;color:white">Hidden ancestor</button></div>' +
        '<button style="background:transparent;color:navy">Outline</button>' +
        '<button style="background:navy;color:white">Buy tickets</button>';
    dom.window.document.body.prepend(candidates);
    message(frame, 'https://tickets.invalid', envelope('ready'));
    const theme = sent[0].at(-1)[0].theme;
    assert.equal(theme.primary, 'rgb(0, 0, 128)');
    assert.equal(theme.buttonText, 'rgb(255, 255, 255)');
    dom.window.close();
});

test('host composites translucent ancestors over the dark page into an opaque background', () => {
    const {dom, frames:[frame], sent, message} = host(true);
    dom.window.document.documentElement.style.backgroundColor = 'rgb(0, 0, 0)';
    dom.window.document.body.style.backgroundColor = 'rgba(100, 100, 100, 0.5)';
    frame.parentElement.style.cssText = 'background:rgba(200, 200, 200, 0.2);color:white';
    message(frame, 'https://tickets.invalid', envelope('ready'));
    const theme = sent[0].at(-1)[0].theme;
    assert.equal(theme.background, 'rgb(80, 80, 80)');
    assert.equal(theme.primary, 'rgb(255, 255, 255)');
    assert.equal(theme.buttonText, 'rgb(80, 80, 80)');
    dom.window.close();
});

test('native colors use a lazy detached canvas and preserve alpha over dark ancestors', () => {
    let calls = 0;
    const colors = new Map([
        ['oklch(0.25 0.05 260)', [19,33,57,255]],
        ['color(display-p3 0.1 0.2 0.3 / 0.5)', [15,52,79,128]],
        ['rebeccapurple', [102,51,153,255]],
    ]);
    const {dom, sent} = host(true, win => {
        win.CSS = {supports: (_, value) => colors.has(value)};
        win.HTMLCanvasElement.prototype.getContext = function () {
            calls++; assert.equal(this.width,1); assert.equal(this.height,1); assert.equal(this.isConnected,false);
            return {fillStyle:'',clearRect(){},fillRect(){},getImageData(){return {data:colors.get(this.fillStyle)};}};
        };
        win.document.body.style.cssText='color:white;--wp--preset--color--primary:rebeccapurple';
        const getStyle = win.getComputedStyle.bind(win);
        win.getComputedStyle = node => {
            const style=getStyle(node);
            const value=node===win.document.body?'oklch(0.25 0.05 260)':node.hasAttribute('data-festapp-embed-host')?'color(display-p3 0.1 0.2 0.3 / 0.5)':null;
            if(value) Object.defineProperty(style,'backgroundColor',{value});
            return style;
        };
    });
    assert.equal(sent[0][0][0].theme.background,'rgb(17, 43, 68)');
    assert.equal(sent[0][0][0].theme.primary,'rgb(102, 51, 153)');
    assert.equal(calls,1); dom.window.close();
});

test('unavailable native color normalization resets an existing host theme safely', () => {
    for(const failure of ['no-support','no-context','readback']) {
        const {dom,frames:[frame],sent,message}=host(false,win=>{
            win.document.body.style.cssText='background:black;color:white';
            if(failure!=='no-support') win.CSS={supports:()=>true};
            win.HTMLCanvasElement.prototype.getContext=()=>{
                if(failure==='no-context') return null;
                if(failure==='no-support') throw Error('must not request canvas without CSS.supports');
                return {fillStyle:'',clearRect(){},fillRect(){},getImageData(){throw Error('blocked');}};
            };
        });
        assert.equal(sent[0][0][0].theme.background,'rgb(0, 0, 0)');
        const getStyle=dom.window.getComputedStyle.bind(dom.window);
        dom.window.getComputedStyle=node=>{
            const style=getStyle(node);
            if(node===dom.window.document.body) Object.defineProperty(style,'backgroundColor',{value:'oklch(0.25 0.05 260)'});
            return style;
        };
        message(frame,'https://tickets.invalid',envelope('ready'));
        assert.equal(sent[0].at(-1)[0].theme,null,failure); dom.window.close();
    }
});

test('unresolved presets and unknown button ancestors retain the safe sampled fallback', () => {
    let calls=0;
    const {dom,sent}=host(false,win=>{
        win.CSS={supports:()=>true};
        win.HTMLCanvasElement.prototype.getContext=()=>{calls++;return null;};
        win.document.body.style.cssText='background:white;color:black;--wp--preset--color--primary:var(--brand)';
        const candidate=win.document.createElement('section');
        candidate.innerHTML='<button style="background:black;color:white">Unknown</button>';
        win.document.body.append(candidate);
        const good=win.document.createElement('button');good.style.cssText='background:rgb(10,20,30);color:white';win.document.body.append(good);
        const getStyle=win.getComputedStyle.bind(win);
        win.getComputedStyle=node=>{
            const style=getStyle(node);
            if(node===candidate) Object.defineProperty(style,'backgroundColor',{value:'oklch(0.25 0.05 260)'});
            return style;
        };
    });
    assert.equal(sent[0][0][0].theme.primary,'rgb(10, 20, 30)');assert.equal(calls,1);dom.window.close();
});

test('legacy host appearance flags never become protocol authority', async () => {
    const {dom,frames:[a,b],sent}=host(false,win=>{
        const [first,second]=win.document.querySelectorAll('iframe');
        first.dataset.festappStyle='inherit';
        second.dataset.festappStyle='default';
        second.dataset.festappHeight='fixed';
    });
    try {
        assert.equal(sent[0][0][0].styleMode,undefined);
        assert.equal(sent[1][0][0].styleMode,undefined);
        assert.equal(sent[1][0][0].autoHeight,false);
        a.dataset.festappStyle='default';
        await new Promise(resolve=>dom.window.requestAnimationFrame(resolve));
        assert.equal(sent[0].at(-1)[0].styleMode,undefined);
        assert.equal(sent[1].at(-1)[0].styleMode,undefined);
        b.dataset.festappStyle='inherit';
        await new Promise(resolve=>dom.window.requestAnimationFrame(resolve));
        assert.equal(sent[1].at(-1)[0].styleMode,undefined);
        assert.equal(sent[1].at(-1)[0].autoHeight,false);
    } finally { dom.window.close(); }
});

test('saved form preference overrides hostile legacy markup in either loading order and height mode',()=>{
    for(const automatic of [true,false]) for(const formEnabled of [true,false])
    for(const styleMode of ['inherit','default']) for(const formFirst of [true,false]) {
        const dom=new JSDOM('<body>Checkout</body>',{url:'https://tickets.invalid/form/a?embed=1',pretendToBeVisual:true});
        const win=dom.window,previous={window:globalThis.window,document:globalThis.document};
        Object.assign(globalThis,{window:win,document:win.document});
        const parent={postMessage(){}};
        Object.defineProperty(win,'parent',{value:parent});
        win.ResizeObserver=class {observe(){} disconnect(){}};
        win.CSS={supports:()=>true};
        const bridge=new EmbedBridge(win); bridge.start();
        const root=win.document.documentElement;
        const message=(origin='https://host.invalid')=>win.dispatchEvent(new win.MessageEvent('message',{
            source:parent,origin,data:envelope('init','appearance',{viewportHeight:600,autoHeight:automatic,styleMode,
                theme:{fontFamily:'serif',text:'black',background:'white',primary:'navy',buttonText:'white'}})
        }));
        try {
            if(formFirst) bridge.setInheritStyle(formEnabled);
            message();
            if(!formFirst) {
                assert.equal(root.dataset.embedTheme,undefined,'presentation waits for form data');
                bridge.setInheritStyle(formEnabled);
            }
            assert.equal(root.dataset.embedTheme,formEnabled?'host':undefined);
            assert.equal(bridge.autoHeight,automatic);
            bridge.setInheritStyle(!formEnabled);
            assert.equal(root.dataset.embedTheme,!formEnabled?'host':undefined,'later form load applies its saved choice');
        } finally { bridge.destroy();win.close();Object.assign(globalThis,previous); }
    }
});

test('heartbeat keeps the lease and rereads the source; hiding the page changes nothing',()=>{
 let heartbeat;const f=host(false,win=>{Object.defineProperty(win.document,'hidden',{value:true,configurable:true});win.setInterval=callback=>{heartbeat=callback;return 1;};win.clearInterval=()=>{};});
 const {dom,frames:[frame],sent,message}=f;const instance=sent[0][0][0].instance;
 const context=manifest=>message(frame,'https://tickets.invalid',envelope('measurement-context',instance,{measurement:{protocol:measurementProtocol,manifest}}),frame.contentWindow);
 context(measurement);let choice={processingRevision:'a',analytics:true,marketing:true},reads=0;
 const disconnect=dom.window.FestappEmbed.connectMeasurementConsent(frame,{read:()=>{reads++;return choice;},subscribe:()=>()=>{}});
 const lease=sent[0].at(-1)[0].measurement.leaseId;assert.ok(lease,'a hidden page still measures');
 const before=reads;heartbeat();assert.ok(reads>before);assert.equal(sent[0].at(-1)[0].measurement.leaseId,lease);
 dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));assert.equal(sent[0].at(-1)[0].measurement.leaseId,lease);
 const layout=reads;dom.window.dispatchEvent(new dom.window.Event('scroll'));assert.equal(reads,layout,'layout does not read the choice');
 choice=null;heartbeat();assert.equal(sent[0].at(-1)[0].measurement.leaseId,lease);assert.deepEqual(plain(sent[0].at(-1)[0].measurement.consent),{analytics:false,marketing:false});
 context({...measurement,processing_revision:'b'});assert.notEqual(sent[0].at(-1)[0].measurement.leaseId,lease,'a new revision gets a new lease');
 disconnect();const disconnectedReads=reads;heartbeat();assert.equal(reads,disconnectedReads,'disconnected source is never reread');dom.window.close();
});

const deniedChoice={analytics:false,marketing:false};
test('cutover: replacing or losing a choice source never reveals an older grant',()=>{
 const f=measurementHost();try{
  f.dom.window.FestappEmbed.setMeasurementConsent(f.frame,{analytics:true,marketing:true});
  const stop=f.dom.window.FestappEmbed.connectMeasurementConsent(f.frame,{read:()=>({processingRevision:'a',...deniedChoice}),subscribe:()=>()=>{}});
  assert.deepEqual(plain(f.last().measurement.consent),deniedChoice);
  const lease=f.last().measurement.leaseId;stop();stop();
  assert.deepEqual(plain(f.last().measurement.consent),deniedChoice);assert.equal(f.last().measurement.leaseId,lease);
  f.dom.window.FestappEmbed.setMeasurementConsent(f.frame,true);
  f.dom.window.FestappEmbed.connectMeasurementConsent(f.frame,{read:()=>true,subscribe(){throw Error('unavailable');}});
  assert.deepEqual(plain(f.last().measurement.consent),deniedChoice);
 }finally{f.dom.window.close();}
});
test('cutover: legacy choice is scoped and an old disposer cannot clear its replacement',()=>{
 const f=measurementHost();try{
  f.dom.window.FestappEmbed.setMeasurementConsent(f.frame,{analytics:true,marketing:true});
  f.send('measurement-context',{measurement:{protocol:measurementProtocol,manifest:{...measurement,processing_revision:'b'}}});
  assert.deepEqual(plain(f.last().measurement.consent),deniedChoice);
  let staleNotify;
  const old=f.dom.window.FestappEmbed.connectMeasurementConsent(f.frame,{read:()=>({processingRevision:'b',...deniedChoice}),subscribe:fn=>{staleNotify=fn;return()=>{};}});
  f.dom.window.FestappEmbed.connectMeasurementConsent(f.frame,{read:()=>({processingRevision:'b',analytics:true,marketing:false}),subscribe:()=>()=>{}});
  old();staleNotify();
  assert.deepEqual(plain(f.last().measurement.consent),{analytics:true,marketing:false});
 }finally{f.dom.window.close();}
});
test('cutover: record owns Klaro subscription and ignores retired watcher updates',async()=>{
 const f=measurementHost();let watcher,unwatched=0;try{
  const manager={confirmed:true,savedConsents:{analytics:true,marketing:true},getConsent:()=>true,watch:w=>{watcher=w;},unwatch(){unwatched++;}};
  const stop=f.dom.window.FestappEmbed.connectKlaro(f.frame,manager);
  f.dom.window.FestappEmbed.setMeasurementConsent(f.frame,false);
  assert.equal(unwatched,1);watcher.update();assert.deepEqual(plain(f.last().measurement.consent),deniedChoice);
  stop();assert.equal(unwatched,1);
 }finally{f.dom.window.close();}
});
test('cutover: retired record heartbeat is removed on origin replacement and pagehide',async()=>{
 const timers=new Map(),polls=new Map();let n=0;
 const f=host(false,win=>{win.setInterval=(fn,delay)=>{(delay===1000?polls:timers).set(++n,fn);return n;};win.clearInterval=id=>{timers.delete(id);polls.delete(id);};});
 const frame=f.frames[0],instance=f.sent[0][0][0].instance;
 const context=(id=instance,origin='https://tickets.invalid')=>f.message(frame,origin,envelope('measurement-context',id,{measurement:{protocol:measurementProtocol,manifest:measurement}}));
 try{
  context();assert.equal(timers.size,1);const retired=[...timers.values()][0];
  frame.src='https://new.invalid/form/b?embed=1';await new Promise(resolve=>setImmediate(resolve));
  assert.equal(timers.size,0);const before=f.sent[0].length;retired();assert.equal(f.sent[0].length,before);
  frame.contentWindow.postMessage=(...args)=>f.sent[0].push(args);
  f.message(frame,'https://new.invalid',envelope('ready'));
  const next=f.sent[0].at(-1)[0].instance;context(next,'https://new.invalid');assert.equal(timers.size,1);
  f.dom.window.dispatchEvent(new f.dom.window.PageTransitionEvent('pagehide',{persisted:true}));assert.equal(timers.size,0);
  f.dom.window.dispatchEvent(new f.dom.window.PageTransitionEvent('pageshow',{persisted:true}));assert.equal(timers.size,1);
  frame.remove();await new Promise(resolve=>setImmediate(resolve));assert.equal(timers.size,0);
  assert.equal(polls.size,0,'consent polling stops with the last embed');
 }finally{f.dom.window.close();}
});

test('cutover: pre-context setter binds once and two frames keep independent scopes',()=>{
 const f=host();const [a,b]=f.frames;try{
  f.dom.window.FestappEmbed.setMeasurementConsent(a,true);
  f.dom.window.FestappEmbed.setMeasurementConsent(b,{analytics:true,marketing:true});
  const context=(frame,index,manifest)=>f.message(frame,new URL(frame.src).origin,envelope('measurement-context',f.sent[index][0][0].instance,{measurement:{protocol:measurementProtocol,manifest}}));
  context(a,0,measurement);context(b,1,{...measurement,organization:2,unit:3});
  assert.deepEqual(plain(f.sent[0].at(-1)[0].measurement.consent),{analytics:true,marketing:false});
  assert.deepEqual(plain(f.sent[1].at(-1)[0].measurement.consent),{analytics:true,marketing:true});
  context(a,0,{...measurement,unit:4});assert.deepEqual(plain(f.sent[0].at(-1)[0].measurement.consent),deniedChoice);
  assert.deepEqual(plain(f.sent[1].at(-1)[0].measurement.consent),{analytics:true,marketing:true});
 }finally{f.dom.window.close();}
});

test('cutover: bridge publishes the complete canonical manifest to the real helper',()=>{
 const f=child();try{
  f.bridge.connectConsent(measurement,()=>{});
  f.init({measurementProtocol,dataLayer:true});
  const context=f.sent.find(([message])=>message.type==='measurement-context')[0].measurement;
  assert.equal(context.protocol,measurementProtocol);assert.deepEqual(context.manifest,{...measurement,measurement_consent_bridge:false});
 }finally{f.done();}
});


test('automatic height starts compactly, preserves no-script fallback and accepts short forms', () => {
    const { dom, frames: [auto, fixed], sent, message } = host(false, win => {
        win.document.querySelectorAll('iframe')[1].dataset.festappHeight = 'fixed';
    });
    assert.equal(auto.getAttribute('height'), '800');
    assert.equal(auto.style.height, '120px');
    assert.equal(fixed.getAttribute('height'), '800');
    assert.equal(fixed.style.height, '');
    assert.equal(sent[0][0][0].minHeight, 120);
    for (const height of [119, -1, NaN, 20001]) {
        message(auto, 'https://tickets.invalid', envelope('resize', sent[0][0][0].instance, {height}));
        assert.equal(auto.style.height, '120px');
    }
    for (const height of [170, 240, 1200]) {
        message(auto, 'https://tickets.invalid', envelope('resize', sent[0][0][0].instance, {height}));
        assert.equal(auto.style.height, `${height}px`);
        message(fixed, 'https://other.invalid', envelope('resize', sent[1][0][0].instance, {height}));
        assert.equal(fixed.style.height, '');
    }
    dom.window.close();
});

test('short child forms negotiate a lower minimum only with a capable protocol-1 host', () => {
    const dom = new JSDOM('<body>Checkout</body>', {url:'https://tickets.invalid/form/a?embed=1', pretendToBeVisual:true});
    const win = dom.window;
    globalThis.document = win.document; globalThis.window = win;
    const sent = [], parent = {postMessage: data => sent.push(data)};
    Object.defineProperty(win, 'parent', {value:parent});
    win.ResizeObserver = class { observe() {} disconnect() {} };
    win.requestAnimationFrame = () => 1;
    win.cancelAnimationFrame = () => {};
    win.document.body.getBoundingClientRect = () => ({height:170});
    const bridge = new EmbedBridge(win); bridge.start();
    for (const [minHeight, expected] of [[undefined,240], [120,170], [0,240], [119,240]]) {
        win.dispatchEvent(new win.MessageEvent('message', {source:parent,origin:'https://host.invalid',
            data:envelope('init','one',{viewportHeight:600,minHeight})}));
        bridge.publishHeight();
        assert.equal(sent.filter(data => data.type === 'resize').at(-1).height, expected);
    }
    bridge.destroy(); dom.window.close();
    delete globalThis.window; delete globalThis.document;
});

test('repeated start and destroyed child cannot send or revive observers', async () => {
    const dom = new JSDOM('<body>Form</body>', {url:'https://tickets.invalid/form/a?embed=1',pretendToBeVisual:true});
    const win=dom.window, sent=[];
    let observed=0;
    Object.defineProperty(win,'parent',{value:{postMessage:(...args)=>sent.push(args)}});
    win.ResizeObserver=class {observe(){observed++;} disconnect(){}};
    const bridge=new EmbedBridge(win);
    bridge.start(); bridge.start();
    assert.equal(observed,1);
    bridge.destroy();
    const count=sent.length;
    win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:'https://host.invalid',
        data:envelope('init','new',{viewportHeight:600})}));
    win.dispatchEvent(new win.Event('pageshow')); bridge.start(); bridge.measure();
    await new Promise(resolve=>win.setTimeout(resolve,220));
    assert.equal(sent.length,count); assert.equal(observed,1);
    win.close();
});

test('retired consent disposer cannot stop the current binding, page lifecycle renews its lease', () => {
    const f=child();
    try {
        f.init({measurementProtocol,dataLayer:true});
        const notify=()=>{};
        const dispose=f.bridge.connectConsent(measurement,notify);
        f.bridge.connectConsent(measurement,notify);
        dispose();
        const before=f.sent.length;
        f.win.dispatchEvent(new f.win.Event('pagehide'));
        f.win.dispatchEvent(new f.win.Event('pageshow'));
        assert.ok(f.sent.length>before);
        assert.equal(f.sent.at(-1)[0].type,'measurement-context');
    } finally { f.done(); }
});

test('a replacement bridge owns the window and a retired destroy cannot clear its theme', () => {
    const dom=new JSDOM('<body>Form</body>',{url:'https://tickets.invalid/form/a?embed=1',pretendToBeVisual:true});
    const win=dom.window; win.ResizeObserver=class {observe(){} disconnect(){}};
    Object.defineProperty(win,'parent',{value:{postMessage(){}}});
    const old=new EmbedBridge(win), current=new EmbedBridge(win);
    old.start(); current.start();
    win.document.documentElement.dataset.embedTheme='host';
    old.destroy(); old.setInheritStyle(false); old.receiveTheme(null);
    assert.equal(win.document.documentElement.dataset.embedTheme,'host');
    assert.equal(old.selection(),null);
    current.destroy(); win.close();
});


test('host transport requires an explicit opt-in and live changes preserve the boundary',async t=>{
 const {dom,frames:[frame],sent}=host();t.after(()=>dom.window.close());
 assert.equal(sent[0][0][0].dataLayer,false);
 for(const [value,enabled] of [['false',true],['',true],['true',true],['FALSE',true],['other',true],['false',true],[null,false]]) {
  const before=sent[0].filter(([m])=>m.type==='init').length;
  if(value===null)frame.removeAttribute('data-festapp-datalayer');else frame.setAttribute('data-festapp-datalayer',value);
  await new Promise(resolve=>setImmediate(resolve));
  const inits=sent[0].filter(([m])=>m.type==='init');
  assert.ok(inits.length>before);assert.equal(inits.at(-1)[0].dataLayer,enabled);
 }
});
test('host context and every event carry strict form_embedded with no host URL data',()=>{
 const f=measurementHost();
 const m={protocol:measurementProtocol,manifest:measurement,generation:1,leaseId:f.last().measurement.leaseId};
 f.send('measurement-activate',{measurement:m});
 const ecommerce={currency:'CZK',items:[{item_id:'product_11',item_name:'Koncert',price:100,quantity:1}]};
 const payloads=[{page_type:'sale_opening',user_type:'b2c',language:'cs'},
  ...['page_view','form_start','form_submit_error'].map(event=>({event})),
  {event:'generate_lead',event_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',currency:'CZK',value:0,lead_source:'waitlist'},
  ...['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase'].map(event=>({event,ecommerce:{...ecommerce,payment_type:'bank_transfer',transaction_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44'}}))];
 for(const payload of payloads)f.send('analytics',{measurement:m,payload:{...payload,form_embedded:false,page_location:'https://host.invalid/private',page_referrer:'https://private.invalid'}});
 const pushes=plain(f.dom.window.dataLayer),events=pushes.filter(p=>p.event||p.page_type);
 assert.equal(events.length,payloads.length);
 assert.equal(events.some(p=>p.event==='page_view'),false);assert.equal(events.filter(p=>p.event==='form_page_view').length,1);
 assert.deepEqual(events[0],{page_type:'sale_opening',user_type:'b2c',language:'cs',form_embedded:true});
 for(const payload of events){assert.equal(payload.form_embedded,true);assert.equal(payload.page_location,undefined);assert.equal(payload.page_referrer,undefined);}
 for(const payload of pushes.filter(p=>!p.event&&!p.page_type&&'form_embedded' in p))assert.equal(payload.form_embedded,false,'host marker is scoped to one measurement push');
 f.frame.removeAttribute('data-festapp-datalayer');
 f.send('analytics',{measurement:m,payload:{event:'page_view'}});assert.equal(f.dom.window.dataLayer.length,pushes.length,'opt-out never writes host events');
 f.dom.window.close();
});

// Model the documented retained dataLayer state at each event, not just the
// standalone push objects. GTM processes these messages in FIFO order.
function retainedMeasurementHost(t) {
 const f=host(),state={},events=[];
 t.after(()=>f.dom.window.close());
 const layer=f.dom.window.dataLayer=[];
 layer.push=(...values)=>{
  for(const value of values){Object.assign(state,value);if(value.event)events.push(plain(state));}
  return Array.prototype.push.apply(layer,values);
 };
 const activate=(index,generation=1,manifest={...measurement,form_link:index===0?'a':'b'})=>{
  const frame=f.frames[index],instance=f.sent[index][0][0].instance;
  frame.setAttribute('data-festapp-datalayer','');
  const send=(type,values)=>f.message(frame,new URL(frame.src).origin,envelope(type,instance,values));
  send('measurement-context',{measurement:{protocol:measurementProtocol,manifest}});
  const leaseId=f.sent[index].findLast(([m])=>m.type==='measurement-consent')[0].measurement.leaseId;
  const grant={protocol:measurementProtocol,manifest,generation,leaseId};
  send('measurement-activate',{measurement:grant});
  return {send,grant,emit:payload=>send('analytics',{measurement:grant,payload})};
 };
 return {...f,layer,state,events,activate};
}

test('embedded marker does not leak into later native website events',t=>{
 const f=retainedMeasurementHost(t),a=f.activate(0);
 a.emit({page_type:'product',language:'cs'});
 f.layer.push({event:'website_after_context'});
 a.emit({event:'page_view'});
 f.layer.push({event:'page_view'});
 a.emit({event:'form_start'});
 f.layer.push({event:'website_after_interaction'});
 assert.deepEqual(f.events.map(({event,form_embedded})=>[event,form_embedded]),[
  ['website_after_context',false],['form_page_view',true],['page_view',false],
  ['form_start',true],['website_after_interaction',false]
 ]);
});

test('interleaved embeds retain their own page context and clear it across grants',t=>{
 const f=retainedMeasurementHost(t),a=f.activate(0),b=f.activate(1);
 a.emit({page_type:'product',language:'cs'});
 b.emit({page_type:'sale_opening',language:'en'});
 a.emit({event:'page_view'});
 b.emit({event:'form_start'});
 a.emit({event:'form_start',page_type:'sale_opening',language:'de'});
 assert.deepEqual(f.events.map(({event,page_type,language})=>[event,page_type,language]),[
  ['form_page_view','product','cs'],['form_start','sale_opening','en'],['form_start','product','cs']
 ]);
 const next=f.activate(0,2);
 a.emit({page_type:'confirmation',language:'de'}); // Retired generation cannot replace context.
 next.emit({event:'form_start'});
 assert.equal(f.events.at(-1).page_type,null);
 assert.equal(f.events.at(-1).language,null);
 next.emit({page_type:'checkout'});
 b.emit({page_type:'sale_opening',language:'en'});
 next.send('measurement-activate',{measurement:next.grant}); // Duplicate ACK preserves current context.
 next.emit({event:'form_start'});
 assert.equal(f.events.at(-1).page_type,'checkout');
 assert.equal(f.events.at(-1).language,null,'missing language never borrows the other frame language');
 const changed=f.activate(0,3,{...measurement,form_link:'a',processing_revision:'new-scope'});
 changed.emit({event:'page_view'});
 assert.equal(f.events.at(-1).page_type,null,'a new scope never reuses the prior page context');
 assert.equal(f.events.at(-1).language,null);
});

test('host sends raw identity only for granted purposes in Unit mode',()=>{
 const f=host();const frame=f.frames[0];try {
  f.dom.window.document.cookie='_ga=GA1.1.123.456; Path=/';
  f.dom.window.document.cookie='_fbp=fb.1.123.456; Path=/';
  const sendContext=()=>f.message(frame,'https://tickets.invalid',envelope('measurement-context',f.sent[0][0][0].instance,{measurement:{protocol:measurementProtocol,manifest:measurement}}));
  sendContext();assert.deepEqual(plain(f.sent[0].at(-1)[0].measurement.hostIdentity),{});
  f.dom.window.FestappEmbed.setMeasurementConsent(frame,true);
  assert.deepEqual(plain(f.sent[0].at(-1)[0].measurement.hostIdentity),{_ga:'GA1.1.123.456'});
  f.dom.window.FestappEmbed.setMeasurementConsent(frame,{marketing:true});
  assert.deepEqual(plain(f.sent[0].at(-1)[0].measurement.hostIdentity),{_fbp:'fb.1.123.456'});
  frame.setAttribute('data-festapp-datalayer','');sendContext();
  assert.equal(f.sent[0].at(-1)[0].measurement.hostIdentity,undefined);
 } finally {f.dom.window.close();}
});

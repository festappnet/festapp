import test from 'node:test';
import assert from 'node:assert/strict';
import {register} from 'node:module';
import {JSDOM} from 'jsdom';
register('../css_loader.mjs',import.meta.url);

// Exercise the real page/bridge/theme chain. Only data transport, the base
// service theme and unrelated status content are simulated.
test('saved form owns embed appearance across both loading orders, navigation and stale responses',async t=>{
    const dom=new JSDOM('<div id="page"></div>',{
        url:'https://tickets.invalid/form/on?embed=1',pretendToBeVisual:true
    });
    const win=dom.window;
    const previous=Object.fromEntries(['window','document','HTMLElement','CustomEvent'].map(key=>[key,globalThis[key]]));
    Object.assign(globalThis,{window:win,document:win.document,HTMLElement:win.HTMLElement,CustomEvent:win.CustomEvent});
    win.scrollTo=()=>{};
    win.ResizeObserver=class {observe(){} disconnect(){}};
    win.CSS={supports:()=>true};
    const parent={postMessage(){}};
    Object.defineProperty(win,'parent',{value:parent});
    const [{FormPage},{DbForms},{FormAvailabilityService},{RightsService},{SeoService},{FormModel},{ThemeService}]=await Promise.all([
        import('../../src/components/forms/form_page.js'),import('../../src/components/forms/db_forms.js'),
        import('../../src/components/forms/form_availability_service.js'),import('../../src/services/rights_service.js'),
        import('../../src/services/seo_service.js'),import('../../src/components/forms/form_models.js'),
        import('../../src/services/theme_service.js')
    ]);
    const page=new FormPage('page');
    t.after(()=>{page.clear();dom.window.close();Object.assign(globalThis,previous);});
    t.mock.method(ThemeService,'applyThemeFromModel',()=>{});
    t.mock.method(RightsService,'canSeeReservations',()=>false);
    t.mock.method(SeoService,'updateMetaTags',()=>{});
    t.mock.method(FormAvailabilityService,'renderStatus',host=>{host.textContent='Form status';return true;});
    const model=(link,enabled)=>new FormModel({link,data:{design:{embed_inherit_style:enabled}}});
    let finish,started;
    let requested=new Promise(resolve=>{started=resolve;});
    t.mock.method(DbForms,'getFormByLink',link=>{
        if(link==='on'||link==='stale')return new Promise(resolve=>{finish=resolve;started();});
        return Promise.resolve(model(link,link!=='off'));
    });
    const theme={fontFamily:'serif',text:'black',background:'white',primary:'navy',buttonText:'white'};
    const message=(extra={})=>win.dispatchEvent(new win.MessageEvent('message',{
        source:parent,origin:'https://host.invalid',data:{namespace:'festapp-embed',protocol:1,type:'init',
            instance:'test',viewportHeight:600,theme,...extra}
    }));
    const root=win.document.documentElement;
    const first=page.init('on');await requested;
    message();
    assert.equal(root.dataset.embedTheme,undefined,'host input cannot bypass pending form settings');
    finish(model('on',true));await first;
    assert.equal(root.dataset.embedTheme,'host');
    message({inheritStyle:false});
    assert.equal(root.dataset.embedTheme,'host','legacy host flags cannot disable saved inheritance');
    await page.init('off');
    assert.equal(root.dataset.embedTheme,undefined);
    message();assert.equal(root.dataset.embedTheme,undefined,'host cannot override a disabled form');
    message({inheritStyle:true});
    assert.equal(root.dataset.embedTheme,undefined,'legacy host flags cannot enable a disabled form');

    requested=new Promise(resolve=>{started=resolve;});
    const stale=page.init('stale');await requested;
    await page.init('off',{forceReload:true});
    finish(model('stale',true));await stale;
    assert.equal(root.dataset.embedTheme,undefined,'a stale form response cannot change appearance');

    page.clear();
    await page.init('on-second');
    assert.equal(root.dataset.embedTheme,undefined,'saved setting may arrive before host presentation');
    message();assert.equal(root.dataset.embedTheme,'host');
    page.clear();assert.equal(root.dataset.embedTheme,undefined);
});

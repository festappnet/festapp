import test from 'node:test';
import assert from 'node:assert/strict';
import {register} from 'node:module';
import {JSDOM} from 'jsdom';
register('../css_loader.mjs', import.meta.url);

test('My events responds immediately, survives rerender, prevents duplicates and recovers for retry', async t => {
    const dom = new JSDOM('<body></body>', {url:'https://vstupenky.online/'});
    Object.assign(globalThis, {window:dom.window, document:dom.window.document,
        HTMLElement:dom.window.HTMLElement, customElements:dom.window.customElements});
    const [{UserHeader}, {RightsService}, {RouterService}, {AppConfig}, {CommonStrings}, {ToastHelper}] = await Promise.all([
        import('../../src/components/users/user_header.js'), import('../../src/services/rights_service.js'),
        import('../../src/services/router_service.js'), import('../../src/app_config.js'),
        import('../../src/components/shared/common_strings.js'), import('../../src/components/ui/toast.js'),
    ]);
    const previous = {context:RightsService._context, link:AppConfig.webLink};
    t.after(() => {RightsService._context=previous.context; AppConfig.webLink=previous.link; dom.window.close();});
    AppConfig.webLink='https://vstupenky.online';
    RightsService._context={user_info:{id:'test-account',name:'Test',units:[]},capabilities:{}};
    let resolve, reject;
    const navigate=t.mock.method(RouterService,'navigateToAdmin',()=>new Promise((yes,no)=>{resolve=yes; reject=no;}));
    const error=t.mock.method(ToastHelper,'showError',()=>{});
    const header=new UserHeader();
    header.setAttribute('data-marketing','');
    document.body.append(header);
    let button=header.querySelector('.btn-admin');
    button.click();
    assert.equal(button.disabled,true);
    assert.equal(button.getAttribute('aria-busy'),'true');
    assert.equal(button.querySelector('.admin-text').textContent,CommonStrings.loading);
    assert.ok(button.querySelector('.admin-loading-spinner'));
    button.click();
    header.render();
    button=header.querySelector('.btn-admin');
    button.click();
    assert.equal(button.disabled,true,'a rights refresh must not reset pending navigation');
    assert.equal(navigate.mock.callCount(),1);
    resolve(); await new Promise(setImmediate);
    assert.equal(button.disabled,true,'keep feedback while the destination document loads');
    window.dispatchEvent(new window.PageTransitionEvent('pageshow',{persisted:true}));
    assert.equal(button.disabled,false,'back/forward restoration allows another navigation');
    assert.equal(button.querySelector('.admin-text').textContent,CommonStrings.myEvents);
    button.click(); reject(new Error('preparation failed'));
    await new Promise(setImmediate);
    assert.equal(button.disabled,false);
    assert.equal(button.getAttribute('aria-busy'),'false');
    assert.equal(error.mock.callCount(),1);
    assert.equal(error.mock.calls[0].arguments[0],CommonStrings.error);
    assert.ok(button.querySelector('.material-icons'));
    button.click();
    assert.equal(navigate.mock.callCount(),3,'failed navigation is retryable');
    resolve(); await new Promise(setImmediate);
    header.remove();
});

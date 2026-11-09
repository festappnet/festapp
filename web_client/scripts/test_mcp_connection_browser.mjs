#!/usr/bin/env node
// Isolated real Chromium, synthetic identity and broker; never production OAuth.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createNativeBrowser} from './native_browser.mjs';
import path from 'node:path';
import { createServer } from 'vite';
const owner=await createNativeBrowser();let context,page,server;
const evaluate=source=>page.evaluate(source);
const measureContrast = async (selector, foreground, background) => evaluate(`(() => {
    const el = document.querySelector(${JSON.stringify(selector)}), style = getComputedStyle(el);
    const context = document.createElement('canvas').getContext('2d');
    const pixel = (color, underneath) => { context.clearRect(0,0,1,1); context.fillStyle=underneath; context.fillRect(0,0,1,1); context.fillStyle=color; context.fillRect(0,0,1,1); return [...context.getImageData(0,0,1,1).data].slice(0,3); };
    const bg=getComputedStyle(document.querySelector('.connection-page')).backgroundColor;
    const lum = rgb => rgb.map(x=>{const v=x/255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);
    const a=lum(pixel(style[${JSON.stringify(foreground)}], bg)), b=lum(pixel(${background === 'page' ? 'bg' : `style[${JSON.stringify(background)}]`}, bg));
    return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);
})()`);
try {
    server=await createServer({configFile:false,root:path.resolve(import.meta.dirname,'..'),logLevel:'error',server:{host:'127.0.0.1',port:0,strictPort:true},plugins:[{name:'mcp-translations',configureServer(vite){vite.middlewares.use(async(req,res,next)=>{
        if(req.url==='/assets/translations/cs.json'){res.setHeader('content-type','application/json');res.end(await readFile(new URL('../../assets/translations/cs.json',import.meta.url)));return;} next();
    });}}]});
    await server.listen();
    const origin=`http://127.0.0.1:${server.httpServer.address().port}`;owner.allow(origin);context=await owner.context();page=await context.newPage();await owner.setTopLevelColorScheme(page,'light');
    const fixtureUrl=`${origin}/tests/fixtures/mcp/index.html`;
    // Exercise the actual theme tokens at representative viewport widths.
    for (const dark of [false, true]) for (const width of [320, 390, 1280]) {
        await page.setViewportSize({width,height:900});
        await page.goto(fixtureUrl+(dark?'?dark=1':''));
        await page.waitForFunction('window.consentFixture?.ready === true');
        assert.equal(await evaluate('document.body.classList.contains("dark-mode")'),dark);
        assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'),true,`consent overflow ${dark}/${width}`);
        const colors = await evaluate(`(() => {
            const root = document.querySelector('.connection-page');
            const color = s => s.match(/[0-9.]+/g).slice(0,3).map(Number);
            const lum = c => { const v=c/255; return v<=.04045?v/12.92:((v+.055)/1.055)**2.4; };
            const contrast = (a,b) => { const x=color(a).map(lum), y=color(b).map(lum); const l=v=>.2126*v[0]+.7152*v[1]+.0722*v[2]; return (Math.max(l(x),l(y))+.05)/(Math.min(l(x),l(y))+.05); };
            const bg=getComputedStyle(root).backgroundColor;
            return { body:contrast(getComputedStyle(root).color,bg), links:[...root.querySelectorAll('a')].map(a=>contrast(getComputedStyle(a).color,bg)) };
        })()`);
        assert.ok(colors.body >= 4.5 && colors.links.every(c=>c >= 4.5),`consent contrast ${dark}/${width}: ${JSON.stringify(colors)}`);
        assert.ok(await measureContrast('button[data-primary]', 'color', 'backgroundColor') >= 4.5, 'disabled text contrast');
        await page.keyboard.press('Tab');
        const focusContrast = await measureContrast(':focus-visible', 'outlineColor', 'page');
        assert.ok(focusContrast >= 3, `focus contrast ${dark}/${width}: ${focusContrast}`);

        await page.locator('input[data-select-all]').first().click();
        await page.getByRole('button',{name:'Povolit a propojit'}).click();
        await page.waitForFunction('window.consentFixture.read().state === "connected"');
        assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'),true,`connected overflow ${dark}/${width}`);
        assert.equal(await evaluate('document.querySelector(".connection-page button").hasAttribute("data-primary")'),true,'close action is primary');
        assert.ok(await measureContrast('button[data-primary]', 'color', 'backgroundColor') >= 4.5, 'close text contrast');
        await page.locator('button[data-primary]').first().hover();
        await page.waitForTimeout(200);
        assert.ok(await measureContrast('button[data-primary]', 'color', 'backgroundColor') >= 4.5, 'hover text contrast');
        assert.equal(await evaluate('document.querySelector(".connection-page").textContent.includes("Codex")'),false,'connected copy is generic');

    }
    await page.goto(fixtureUrl);
    await page.waitForFunction('window.consentFixture?.ready === true');
    await page.setViewportSize({width:1280,height:1000});

    await page.locator('input[data-occasion="99"]').first().click();

    assert.equal(await evaluate('document.querySelector("[data-select-all]").indeterminate'),true);
    await page.locator('input[data-select-all]').first().click();

    assert.deepEqual(await evaluate('consentFixture.read().selected'),[99,100]);
    assert.equal(await evaluate('consentFixture.read().operations.length'),1);
    await page.locator('input[data-select-all]').first().click();

    assert.equal(await evaluate('consentFixture.read().selected.length'),0);
    await page.locator('input[data-select-all]').first().click();

    assert.deepEqual(await evaluate('consentFixture.read().selected'),[99,100]);
    await page.getByRole('button',{name:'Povolit a propojit'}).click();
    await page.waitForFunction('window.consentFixture.read().state === "connected"');
    assert.deepEqual(await evaluate('consentFixture.read().operations.map(o=>o.operation)'),['details','approve','status']);
    assert.deepEqual(await evaluate('consentFixture.read().operations[1].access.selection.occasionIds'),[99,100]);
    assert.equal(await evaluate('consentFixture.read().openerIsNull'),true);
    assert.equal(await evaluate('consentFixture.read().popupClosed'),true);
    assert.equal(await evaluate('performance.getEntriesByType("resource").some(r=>/flutter|main\\.dart|canvaskit/.test(r.name))'),false);
    await page.goto(fixtureUrl+'?many=1');
    await page.waitForFunction('window.consentFixture?.ready === true && window.consentFixture.read().state === "consent"');

    assert.equal(await evaluate('[...document.querySelectorAll("[data-unit-toggle]")].every(b=>b.getAttribute("aria-expanded")==="false")'),true);
    await page.locator('[data-unit-toggle="3"]').first().click();

    await page.locator('input[data-occasion="99"]').first().click();

    assert.equal(await evaluate(`document.querySelector('[data-unit-toggle="3"]').getAttribute('aria-expanded')`), 'true');
    assert.equal(await evaluate('document.activeElement.dataset.occasion'),'99');
    await page.keyboard.press('Shift+Tab');
    assert.equal(await evaluate('document.activeElement.dataset.unitToggle'),'3');
    await page.keyboard.press('Enter');

    assert.equal(await evaluate(`document.querySelector('[data-unit-toggle="3"]').getAttribute('aria-expanded')`),'false');
    await page.keyboard.press('Enter');

    assert.equal(await evaluate(`document.querySelector('[data-unit-toggle="3"]').getAttribute('aria-expanded')`),'true');
    await page.goto(fixtureUrl+'?tree=1');
    await page.waitForFunction('window.consentFixture?.ready === true && window.consentFixture.read().state === "consent"');
    await page.setViewportSize({width:320,height:900});
    await page.evaluate("document.body.style.cssText='margin:0;background:#222629;color:#f3f3f3;font:16px system-ui'");

    assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'),true,'tree fits mobile viewport');
    assert.equal(await evaluate('document.querySelector("[data-whole-unit]") === null'),true);
    await page.locator('input[data-unit="3"]').first().click();
    await page.waitForFunction('window.consentFixture.read().access.units?.some(u=>u.unitId === 3)');

    await page.locator('input[data-unit="4"]').first().click();

    assert.deepEqual(await evaluate('consentFixture.read().access'),{type:'selection',units:[{unitId:3,canCreateOccasions:true},{unitId:4,canCreateOccasions:true}],occasionIds:[]});
    assert.equal(await evaluate('[...document.querySelectorAll("[data-occasion]")].every(i=>i.checked && i.disabled)'),true);
    assert.equal(await evaluate('document.querySelector("[data-permission]") === null'),true);
    assert.equal(await evaluate('document.querySelector(".mcp-access-summary").textContent.includes("ruční platby")'),true);

    await page.setViewportSize({width:1280,height:1000});

    await page.getByRole('button',{name:'Povolit a propojit'}).click();
    await page.waitForFunction('window.consentFixture.read().state === "connected"');
    assert.equal(await evaluate('consentFixture.read().operations[1].access.selection.units.length'),2);
    assert.deepEqual(await evaluate('consentFixture.read().operations[1].access.permissions'),['festapp:orders:read','festapp:orders:write','festapp:payments:write','festapp:tickets:send']);
    await page.goto(fixtureUrl.replace('/mcp/index.html','/connections/index.html'));
    await page.waitForFunction('window.connectionsFixture?.ready === true');
    await page.setViewportSize({width:320,height:900});
    await page.evaluate("document.head.insertAdjacentHTML('beforeend', '<link rel=stylesheet href=/src/theme_config.css>'); document.body.classList.add('dark-mode')");
    await page.waitForFunction('getComputedStyle(document.body).marginLeft === "0px"');

    assert.ok(await measureContrast('.connection-page', 'color', 'page') >= 4.5, 'account text contrast');
    assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'),true,'account connections fit mobile');
    assert.equal(await evaluate('document.body.textContent.includes("Způsoby přihlášení") && document.body.textContent.includes("Připojené aplikace")'),true);
    await page.locator('[data-revoke="first-grant"]').first().click();

    assert.equal(await evaluate('document.activeElement.hasAttribute("data-confirm-revoke")'),true);
    assert.equal(await evaluate('connectionsFixture.read().operations.length'),1,'opening confirmation does not revoke');

    await page.setViewportSize({width:1280,height:1000});

    await page.keyboard.press('Enter');
    await page.waitForFunction('window.connectionsFixture.read().connections.length === 0');

    assert.deepEqual(await evaluate('connectionsFixture.read().operations[1]'),{operation:'connections.revoke',connectionId:'first-grant'});
    await page.locator('[data-google-action]').first().click();
    assert.deepEqual(await evaluate('connectionsFixture.read().googleCalls'),['unlink']);
    console.log('mcp-account-browser: pass (consent and account management; mobile/dark, keyboard, synthetic auth/broker)');
} finally { try { await owner.close(); } finally { await server?.close(); } }

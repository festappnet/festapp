// Browser half of the disposable CMS fixture. The CMP API is deliberately modeled.
// All targets must be task-owned loopback services; the backend marker is mandatory.
import assert from 'node:assert/strict';
import pg from 'pg';
import {createNativeBrowser} from './native_browser.mjs';
const required = name => {const value=process.env[name];assert.ok(value,`${name} is required`);return value;};
const localOrigin = name => {const value=required(name),url=new URL(value);assert.ok(url.protocol==='https:' && url.hostname==='127.0.0.1' && url.port && url.origin===value,`${name} must be an explicit HTTPS loopback origin`);return value;};
const site=localOrigin('FESTAPP_CMS_TEST_SITE');
const service=localOrigin('FESTAPP_CMS_TEST_SERVICE');
const api=localOrigin('FESTAPP_CMS_TEST_API');
const database=new URL(required('FESTAPP_CMS_TEST_DATABASE'));
assert.ok(['postgres:','postgresql:'].includes(database.protocol) && database.hostname==='127.0.0.1' && database.port,'database must be explicit loopback');
const marker=required('FESTAPP_CMS_TEST_MARKER');
assert.match(marker,/^festapp-cms-consent-[a-z0-9-]+$/);
const actor=required('FESTAPP_CMS_TEST_ACTOR');
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
assert.match(actor,uuid);
const db=new pg.Client({connectionString:database.href});
await db.connect();
try { assert.equal((await db.query('select project from festapp_test_support.disposable_environment where singleton')).rows[0]?.project,marker,'foreign database refused'); }
catch (error) { await db.end(); throw error; }
const engine=process.env.FESTAPP_CMS_TEST_ENGINE || 'chromium';
let owner;
try { owner=await createNativeBrowser({engine}); } catch (error) { await db.end(); throw error; }
for(const origin of [site,service,api]) owner.allow(origin);
try {
  if (process.env.FESTAPP_CMS_TEST_IFRAME === '1') {
    const iframeContext=await owner.context({ignoreHTTPSErrors:true});
    try {
      await iframeContext.addInitScript(()=>{window.__testEmbedMessages=[];addEventListener('message',event=>{if(event.data?.namespace==='festapp-embed')window.__testEmbedMessages.push(event.data.type);});});
      const host=await iframeContext.newPage();await host.clock.install();
      await host.goto(site+(process.env.FESTAPP_CMS_TEST_PATH || '/'));
      await host.locator('iframe').first().waitFor({timeout:15000});const frame=host.frameLocator('iframe').first();
      await frame.locator('form').waitFor({timeout:30000});
      await frame.locator('body').evaluate(()=>new Promise((resolve,reject)=>{const timeout=setTimeout(()=>{clearInterval(timer);reject(new Error('initial embed consent missing'));},15000);const timer=setInterval(()=>{if(window.__testEmbedMessages.includes('measurement-consent')){clearTimeout(timeout);clearInterval(timer);resolve();}},100);}));
      // The host owns embedded consent; a second CMP must never block checkout.
      assert.equal(await frame.locator('#festapp-measurement-consent').count(),0,'embed created a local consent controller');
      assert.equal(await frame.locator('.festapp-consent-fab').count(),0,'embed rendered the consent settings button');
      assert.equal(await frame.locator('body').evaluate(body=>body.classList.contains('festapp-consent-space')),false,'embed reserved consent button clearance');
      const count=await frame.locator('body').evaluate(()=>window.__testEmbedMessages.filter(type=>type==='measurement-consent').length);
      // Exercise the real 20s renewal interval without spending 20 wall seconds.
      // The browser timer, postMessage bridge and backend remain the real code.
      await host.clock.fastForward(21000);
      await frame.locator('body').evaluate((_element,before)=>new Promise((resolve,reject)=>{const timeout=setTimeout(()=>{clearInterval(timer);reject(new Error('embed renewal stopped: before='+before+' messages='+JSON.stringify(window.__testEmbedMessages)));},30000);const timer=setInterval(()=>{if(window.__testEmbedMessages.filter(type=>type==='measurement-consent').length>before){clearTimeout(timeout);clearInterval(timer);resolve();}},250);}),count);
      assert.equal(await frame.locator('.festapp-consent-fab').count(),0,'embed rendered the consent settings button after renewal');
      assert.equal(await frame.locator('#festapp-measurement-consent').count(),0,'embed created a local notice after renewal');
    } finally { await iframeContext.close(); }
  }
  const context=await owner.context({ignoreHTTPSErrors:true});
  await context.addInitScript(()=>{window.__testConsentMessages=[];addEventListener('message',event=>{if(event.data?.namespace==='festapp-consent-link')window.__testConsentMessages.push({origin:event.origin,data:event.data});});});
  const page=await context.newPage();
  const siteResponse=await page.goto(site+(process.env.FESTAPP_CMS_TEST_PATH || '/'));
  assert.ok(siteResponse?.ok(), `CMS fixture page returned ${siteResponse?.status()}`);
  await page.locator('[data-festapp-consent-link]').first().waitFor({timeout:15000});
  assert.equal(await page.locator('[data-festapp-consent-link]').count(),1,'fixture owns one marked link');
  const [child]=await Promise.all([page.waitForEvent('popup'),page.locator('[data-festapp-consent-link]').click()]);
  await child.waitForSelector('form',{timeout:30000});
  if (process.env.FESTAPP_CMS_EXPECT_COOP === '1') {
    assert.equal(siteResponse.headers()['cross-origin-opener-policy'],'same-origin','fixture did not preserve Joomla COOP');
    assert.equal(await child.evaluate(()=>!!window.opener),false,'COOP did not sever opener');
    await child.locator('#festapp-measurement-consent .cn-decline').waitFor({state:'visible',timeout:15000});
    assert.equal(await child.evaluate(()=>window.__testConsentMessages.some(x=>x.data.type==='response')),false,'blocked COOP unexpectedly imported a choice');
    console.log(`PASS ${engine} COOP blocks import; form and local notice remain available`);
  } else {
  await child.waitForFunction(()=>window.__testConsentMessages.some(x=>x.data.type==='response' && x.data.choice?.analytics===true && x.data.choice?.marketing===true),null,{timeout:15000});
  await page.evaluate(()=>{
    if (typeof window.__festappTestSetConsent === 'function') window.__festappTestSetConsent(false);
    else { window.testChoice=false; dispatchEvent(new Event('cc:onChange')); }
  });
  await child.waitForFunction(()=>window.__testConsentMessages.some(x=>x.data.type==='response' && x.data.choice?.analytics===false && x.data.choice?.marketing===false),null,{timeout:15000});
  let active=child;
  if (process.env.FESTAPP_CMS_TEST_WITHDRAWAL === '1') {
    await page.evaluate(()=>{if(typeof window.__festappTestSetConsent!=='function')throw new Error('modeled CMP setter missing');window.__festappTestSetConsent(null);});
    await child.waitForFunction(()=>window.__testConsentMessages.some(x=>x.data.type==='end'),null,{timeout:15000});
    await page.evaluate(()=>window.__festappTestSetConsent(true));
    [active]=await Promise.all([page.waitForEvent('popup'),page.locator('[data-festapp-consent-link]').click()]);
    await active.waitForSelector('form',{timeout:30000});
    await active.waitForFunction(()=>window.__testConsentMessages.some(x=>x.data.type==='response' && x.data.choice?.analytics===true),null,{timeout:15000});
  }
  const binding=await active.evaluate(()=>window.__testConsentMessages.find(x=>x.data.type==='response').data.scope.binding);
  assert.match(binding.id,uuid);assert.ok(Number.isSafeInteger(binding.version) && binding.version>0);
  await db.query('BEGIN');
  try {
    await db.query("select set_config('request.jwt.claim.sub',$1,true), set_config('request.jwt.claim.role','authenticated',true)",[actor]);
    await db.query('select public.disable_unit_website_consent_binding($1::uuid,$2::bigint)',[binding.id,binding.version]);
    await db.query('COMMIT');
  } catch(error) { await db.query('ROLLBACK'); throw error; }
  await active.evaluate(()=>dispatchEvent(new Event('pageshow')));
  await active.waitForFunction(()=>window.__testConsentMessages.some(x=>x.data.type==='end'),null,{timeout:15000});
  const policyResponse=context.waitForEvent('response',{predicate:response=>response.url().includes('/rpc/get_form_measurement_policy') && response.ok(),timeout:30000});
  const [stale]=await Promise.all([page.waitForEvent('popup'),page.locator('[data-festapp-consent-link]').click()]);
  await stale.waitForSelector('form',{timeout:30000});const policy=await (await policyResponse).json();
  assert.ok(policy.website_consent_bindings?.some(item=>item.id===binding.id && item.effective===false && item.version>binding.version),'disabled binding missing from public policy');
  await stale.locator('#festapp-measurement-consent .cn-decline').waitFor({state:'visible',timeout:15000});
  assert.equal(await stale.evaluate(()=>window.__testConsentMessages.some(x=>x.data.type==='response')),false,'stale export granted after disable');
  console.log(`PASS ${engine} real CMS/form grant, refusal${process.env.FESTAPP_CMS_TEST_WITHDRAWAL === '1' ? ', source withdrawal' : ''}, disable refresh and stale export (modeled CMP)`);
  }
} finally { try { await owner.close(); } finally { await db.end(); } }

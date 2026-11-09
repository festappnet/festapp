import test from 'node:test';
import assert from 'node:assert/strict';
import { isolatedBrowserInvocation, openIsolatedBrowser } from '../../scripts/isolated_browser_startup.mjs';

function fixture(sessions) {
    const calls = [];
    return {
        calls,
        open: async () => { calls.push('open'); },
        info: async () => { calls.push('info'); return sessions.shift(); },
        close: async () => { calls.push('close'); },
    };
}

test('lost startup daemon is replaced before checking page isolation', async () => {
    const browser = fixture([{ active: false, runtime: null }, { runtime: { pageCount: 1 } }]);
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info', 'close', 'open', 'info']);
});

test('a healthy daemon opens once', async () => {
    const browser = fixture([{ runtime: { pageCount: 1 } }]);
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info']);
});

test('repeated startup loss fails after three task-owned sessions', async () => {
    const browser = fixture(Array.from({ length: 3 }, () => ({ runtime: null })));
    await assert.rejects(openIsolatedBrowser(browser), /daemon disappeared/);
    assert.equal(browser.calls.filter(call => call === 'open').length, 3);
    assert.equal(browser.calls.filter(call => call === 'close').length, 3);
});

test('wrong isolation is a failure, never a startup retry', async () => {
    const browser = fixture([{ runtime: { pageCount: 2 } }]);
    await assert.rejects(openIsolatedBrowser(browser), /isolated local Chromium required/);
    assert.deepEqual(browser.calls, ['open', 'info']);
});

test('navigation errors propagate without retrying page actions', async () => {
    const browser = fixture([]);
    browser.open = async () => { throw new Error('navigation failed'); };
    await assert.rejects(openIsolatedBrowser(browser), /navigation failed/);
    assert.deepEqual(browser.calls, []);
});

test('timed out launch continues only after a healthy owned daemon is confirmed', async () => {
    const browser = fixture([{ runtime: { pageCount: 1 } }]);
    browser.open = async () => { browser.calls.push('open'); throw Object.assign(new Error('timed out'), { killed: true, signal: 'SIGTERM' }); };
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info']);
});

test('a non-timeout launch error remains fatal', async () => {
    const browser = fixture([]);
    browser.open = async () => { throw Object.assign(new Error('launch failed'), { killed: false, signal: 'SIGTERM' }); };
    await assert.rejects(openIsolatedBrowser(browser), /launch failed/);
    assert.deepEqual(browser.calls, []);
});


test('a launched browser without a page retries only startup before page assertions', async () => {
    const browser = fixture([{ runtime: { pageCount: 0 } }, { runtime: { pageCount: 1 } }]);
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info', 'close', 'open', 'info']);
});

test('repeated empty browser startup is bounded to three fresh sessions', async () => {
    const browser = fixture(Array.from({ length: 3 }, () => ({ runtime: { pageCount: 0 } })));
    await assert.rejects(openIsolatedBrowser(browser), /opened no page/);
    assert.deepEqual(browser.calls, ['open', 'info', 'close', 'open', 'info', 'close', 'open', 'info', 'close']);
});

test('lost blank target after navigation is replaced before page assertions', async () => {
    const browser = fixture(Array.from({ length: 4 }, () => ({ runtime: { pageCount: 1 } })));
    const urls = ['about:blank', 'http://127.0.0.1/test'];
    browser.targetUrl = 'http://127.0.0.1/test';
    browser.navigate = async () => { browser.calls.push('navigate'); };
    browser.currentUrl = async () => { browser.calls.push('url'); return urls.shift(); };
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info', 'navigate', 'info', 'url', 'close', 'open', 'info', 'navigate', 'info', 'url']);
});

test('unexpected nonblank navigation fails without replacing the page', async () => {
    const browser = fixture([{ runtime: { pageCount: 1 } }, { runtime: { pageCount: 1 } }]);
    browser.targetUrl = 'http://127.0.0.1/test';
    browser.navigate = async () => {};
    browser.currentUrl = async () => 'http://127.0.0.1/other';
    await assert.rejects(openIsolatedBrowser(browser), /Unexpected browser navigation/);
    assert.equal(browser.calls.includes('close'), false);
});

test('initial readiness recovers the reported lost CDP setup session before any page actions',async()=>{
 const browser=fixture(Array.from({length:4},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/test';browser.navigate=async()=>{};browser.currentUrl=async()=>browser.targetUrl;
 let reads=0;browser.ready=async()=>{reads++;if(reads===1)throw Object.assign(new Error('CLI failed'),{stdout:JSON.stringify({success:false,error:'Failed to install browser network controls: CDP error (Fetch.enable): Session with given id not found.'})});};
 await openIsolatedBrowser(browser);
 assert.equal(reads,2);assert.equal(browser.calls.filter(c=>c==='open').length,2);assert.equal(browser.calls.filter(c=>c==='close').length,1);
});

test('initial readiness keeps real UI failures fatal instead of retrying them',async()=>{
 const browser=fixture(Array.from({length:2},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/test';browser.navigate=async()=>{};browser.currentUrl=async()=>browser.targetUrl;
 browser.ready=async()=>{throw new Error('Expected header did not become visible');};
 await assert.rejects(openIsolatedBrowser(browser),/Expected header/);
 assert.equal(browser.calls.filter(c=>c==='open').length,1);assert.equal(browser.calls.includes('close'),false);
});

test('repeated CDP setup loss during initial readiness fails after three fresh sessions',async()=>{
 const browser=fixture(Array.from({length:6},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/test';browser.navigate=async()=>{};browser.currentUrl=async()=>browser.targetUrl;
 browser.ready=async()=>{throw Object.assign(new Error('CLI failed'),{stdout:JSON.stringify({success:false,error:'Failed to install browser network controls: CDP error (Fetch.enable): Session with given id not found.'})});};
 await assert.rejects(openIsolatedBrowser(browser),/after 3 fresh sessions/);
 assert.equal(browser.calls.filter(c=>c==='open').length,3);assert.equal(browser.calls.filter(c=>c==='close').length,3);
});

for(const phase of ['open','navigate'])test(`lost CDP setup session during ${phase} recovers only startup`,async()=>{
 const browser=fixture(Array.from({length:4},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/test';browser.navigate=async()=>{};browser.currentUrl=async()=>browser.targetUrl;
 let calls=0;browser[phase]=async()=>{browser.calls.push(phase);if(++calls===1)throw Object.assign(new Error('CLI failed'),{stdout:JSON.stringify({success:false,error:'Failed to install browser network controls: CDP error (Fetch.enable): Session with given id not found.'})});};
 await openIsolatedBrowser(browser);
 assert.equal(calls,2);assert.equal(browser.calls.filter(c=>c==='close').length,1);
});

test('an ordinary navigation failure remains fatal',async()=>{
 const browser=fixture([{runtime:{pageCount:1}}]);browser.targetUrl='http://127.0.0.1/test';
 browser.navigate=async()=>{throw new Error('Navigation failed');};
 await assert.rejects(openIsolatedBrowser(browser),/Navigation failed/);assert.equal(browser.calls.includes('close'),false);
});

test('startup accepts only an explicitly expected URL normalization',async()=>{
 const browser=fixture([{runtime:{pageCount:1}},{runtime:{pageCount:1}}]);
 browser.targetUrl='http://127.0.0.1/test?scenario=guest-open';browser.normalizedUrl='http://127.0.0.1/test';
 browser.navigate=async()=>{};browser.currentUrl=async()=>browser.normalizedUrl;
 await openIsolatedBrowser(browser);assert.equal(browser.calls.filter(c=>c==='open').length,1);
});

test('a different query remains an unexpected navigation',async()=>{
 const browser=fixture([{runtime:{pageCount:1}},{runtime:{pageCount:1}}]);
 browser.targetUrl='http://127.0.0.1/test?scenario=guest-open';browser.normalizedUrl='http://127.0.0.1/test';
 browser.navigate=async()=>{};browser.currentUrl=async()=>browser.normalizedUrl+'?other=1';
 await assert.rejects(openIsolatedBrowser(browser),/Unexpected browser navigation/);assert.equal(browser.calls.includes('close'),false);
});


test('a live blank tab waits for its in-flight navigation before exact URL checks', async () => {
 const browser=fixture(Array.from({length:3},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/test?scenario=guest';
 browser.normalizedUrl='http://127.0.0.1/test';
 const urls=['about:blank',browser.normalizedUrl];
 browser.navigate=async()=>{browser.calls.push('navigate')};
 browser.currentUrl=async()=>{browser.calls.push('url');return urls.shift()};
 browser.waitForNavigation=async()=>{browser.calls.push('wait')};
 await openIsolatedBrowser(browser);
 assert.deepEqual(browser.calls,['open','info','navigate','info','url','wait','info','url']);
});

test('a delayed navigation still rejects an unexpected final URL', async () => {
 const browser=fixture(Array.from({length:3},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/test';
 const urls=['about:blank','http://127.0.0.1/other'];
 browser.navigate=async()=>{}; browser.currentUrl=async()=>urls.shift();browser.waitForNavigation=async()=>{};
 await assert.rejects(openIsolatedBrowser(browser),/Unexpected browser navigation/);
 assert.equal(browser.calls.includes('close'),false);
});


test('a vanished page is not queried in a way that can relaunch a blank browser', async () => {
 const browser=fixture([{runtime:{pageCount:1}},{runtime:{pageCount:0}},
                        {runtime:{pageCount:1}},{runtime:{pageCount:1}}]);
 browser.targetUrl='http://127.0.0.1/test'; browser.navigate=async()=>{};
 let reads=0; browser.currentUrl=async()=>{reads++;return browser.targetUrl};
 await openIsolatedBrowser(browser);
 assert.equal(reads,1); assert.equal(browser.calls.filter(call=>call==='close').length,1);
});


test('exact CLI CDP loss during viewport and first frame check retries before interactions', async () => {
 const browser=fixture(Array.from({length:4},()=>({runtime:{pageCount:1}})));
 browser.targetUrl='http://127.0.0.1/host';
 browser.navigate=async()=>{browser.calls.push('navigate')};
 browser.currentUrl=async()=>browser.targetUrl;
 let waits=0;
 browser.ready=async()=>{
  browser.calls.push('viewport'); browser.calls.push('frame-check');
  if (++waits===1) throw Object.assign(new Error('CLI failed'),{
   stdout:'{"error":"Failed to install browser network controls: CDP error (Fetch.enable): Session with given id not found.","success":false}\n'
  });
 };
 await openIsolatedBrowser(browser);
 browser.calls.push('interaction');
 assert.equal(waits,2);
 assert.equal(browser.calls.filter(c=>c==='close').length,1);
 assert.deepEqual(browser.calls.filter(c=>['viewport','frame-check','interaction'].includes(c)),
  ['viewport','frame-check','viewport','frame-check','interaction']);
});


test('fresh sessions receive containment and later calls do not reapply launch settings', () => {
 const sourceEnv={PATH:'/bin', AGENT_BROWSER_EXECUTABLE_PATH:'/owned/chrome', AGENT_BROWSER_ARGS:'--ignored', AGENT_BROWSER_ALLOWED_DOMAINS:'untrusted.test'};
 const base={session:'owned',launchConfig:'/owned/launch.json',followConfig:'/owned/follow.json',sourceEnv,args:['snapshot','-i']};
 const first=isolatedBrowserInvocation({...base,launch:true});
 assert.ok(first.args.includes('--allowed-domains')); assert.ok(first.args.includes('--headed'));
 assert.equal(first.env.AGENT_BROWSER_EXECUTABLE_PATH,'/owned/chrome');
 assert.equal(first.env.AGENT_BROWSER_ALLOWED_DOMAINS,undefined); assert.equal(first.env.AGENT_BROWSER_ARGS,undefined);
 const next=isolatedBrowserInvocation({...base,launch:false});
 assert.ok(!next.args.includes('--allowed-domains')); assert.ok(!next.args.includes('--headed'));
 assert.equal(next.env.AGENT_BROWSER_EXECUTABLE_PATH,undefined); assert.equal(next.env.AGENT_BROWSER_CONFIG,'/owned/follow.json');
 assert.equal(next.env.AGENT_BROWSER_ALLOWED_DOMAINS,undefined); assert.equal(next.env.AGENT_BROWSER_ARGS,undefined);
});


test('direct target launch verifies isolation and URL without navigating twice', async () => {
    const browser = fixture([{ runtime: { pageCount: 1 } }]);
    browser.targetUrl = 'http://127.0.0.1/test?scenario=one';
    browser.normalizedUrl = 'http://127.0.0.1/test';
    browser.launchAtTarget = true;
    browser.currentUrl = async () => { browser.calls.push('url'); return browser.normalizedUrl; };
    browser.navigate = async () => { browser.calls.push('navigate'); };
    browser.ready = async () => { browser.calls.push('ready'); };
    await openIsolatedBrowser(browser);
    assert.deepEqual(browser.calls, ['open', 'info', 'url', 'ready']);
});

test('direct target launch falls back only from a blank page and rejects a different URL', async () => {
    const browser = fixture([{ runtime: { pageCount: 1 } }, { runtime: { pageCount: 1 } }]);
    browser.targetUrl = 'http://127.0.0.1/test';
    browser.launchAtTarget = true;
    const urls = ['about:blank', browser.targetUrl];
    browser.currentUrl = async () => urls.shift();
    browser.navigate = async () => { browser.calls.push('navigate'); };
    await openIsolatedBrowser(browser);
    assert.equal(browser.calls.filter(call => call === 'navigate').length, 1);
    const wrong = fixture([{ runtime: { pageCount: 1 } }]);
    wrong.targetUrl = browser.targetUrl; wrong.launchAtTarget = true;
    wrong.currentUrl = async () => 'http://127.0.0.1/other';
    wrong.navigate = async () => { throw new Error('must not navigate'); };
    await assert.rejects(openIsolatedBrowser(wrong), /Unexpected browser navigation/);
});

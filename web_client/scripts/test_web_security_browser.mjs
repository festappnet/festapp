#!/usr/bin/env node
// Real isolated Chromium. Synthetic components only; no production data/network.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createServer} from 'vite';
import {Readable} from 'node:stream';
import {scriptPolicy} from '../../automation/lib/csp_policy.mjs';
const execute = promisify(execFile);
const temporary = await mkdtemp(path.join(tmpdir(), 'festapp-security-browser-'));
const config = path.join(temporary,'browser.json');
await writeFile(config, JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false}));
const session = `security-${process.pid}`;
let server;
let acceptedReports = 0;
const buildScript = await readFile(new URL('../../automation/cloudflare_build.sh', import.meta.url), 'utf8');
const workerSource = buildScript.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1];
const {default: reportWorker} = await import('data:text/javascript;base64,' + Buffer.from(workerSource).toString('base64'));
async function browser(...args) {
 const {stdout} = await execute('agent-browser',['--config',config,'--headed','false','--session',session,'--allowed-domains','127.0.0.1','--json',...args],{timeout:30000,env:{...process.env,AGENT_BROWSER_CONFIG:config,AGENT_BROWSER_PLUGINS:'[]'}});
 const response = JSON.parse(stdout);assert.equal(response.success,true,response.error);return response.data;
}
const evaluate = async source => (await browser('eval',source)).result;
try {
 server = await createServer({root:path.resolve(import.meta.dirname,'..'),logLevel:'error',server:{host:'127.0.0.1',port:0,strictPort:true},plugins:[{name:'security-fixture-headers',configureServer(server){server.middlewares.use(async (req,res,next)=>{
  if(req.url.startsWith('/_security/csp-report')) {
   const request = new Request('http://127.0.0.1' + req.url,{method:req.method,headers:req.headers,body:Readable.toWeb(req),duplex:'half'});
   const response = await reportWorker.fetch(request,{});
   if(response.status === 204) acceptedReports++;
   res.writeHead(response.status,Object.fromEntries(response.headers));res.end();return;
  }
  if(req.url.includes('/tests/fixtures/security/index.html') && req.url.includes('enforce=1')) res.setHeader('Content-Security-Policy',scriptPolicy('webclient',[]));
  next();
 });}}]});
 await server.listen();
 for(const enforce of [false,true]) {
  await browser('open',`http://127.0.0.1:${server.httpServer.address().port}/tests/fixtures/security/index.html?enforce=${enforce?1:0}`);
  await browser('wait','--fn','window.securityFixture?.ready === true');
  assert.equal((await browser('session','info')).runtime.pageCount,1);
  await evaluate('window.securityFixture.show()');
  await browser('snapshot','-i');
  assert.equal(await evaluate('document.querySelector(".dialog-description b").textContent'),'Bold');
  assert.equal(await evaluate('document.querySelectorAll("[onload], [onerror], .btn-reserve img, h2 img, a[href^=\\"javascript:\\"]").length'),0);
  await browser('click','.btn-reserve');
  assert.equal(await evaluate('window.securityFixture.reserved'),1);
  await evaluate('window.securityFixture.show()');
  await browser('press','Escape');
  assert.equal(await evaluate('document.body.style.overflow'),'');
  await browser('wait','--fn','document.querySelectorAll(".overlay").length === 0');
  assert.equal(await evaluate('window.securityFixture.executed'),0,'XSS must fail without CSP too');
  if(enforce) {
   await evaluate(`const b=document.createElement('button');b.textContent='Synthetic inline';b.setAttribute('onclick','window.securityFixture.executed++');document.body.appendChild(b);b.click();`);
   await browser('wait','--fn',`window.securityFixture.violations.some(v=>v.directive==='script-src-attr'&&v.disposition==='enforce')`);
   assert.equal(await evaluate('window.securityFixture.executed'),0);
   assert.equal(await evaluate(`fetch('/_security/csp-report?profile=webclient',{method:'POST',headers:{'content-type':'application/csp-report'},body:JSON.stringify({'csp-report':{'effective-directive':'script-src-attr','blocked-uri':'inline',disposition:'enforce'}})}).then(r=>r.status)`),204);
   assert.ok(acceptedReports>0,'real Worker report route accepted browser synthetic violation');
  }
 }
 console.log('web-security-browser: pass (no CSP + enforcing fixture; dialog, reserve callback, Escape, blocked inline handler)');
} finally {
 await browser('close').catch(()=>{});
 await server?.close();await rm(temporary,{recursive:true,force:true});
}

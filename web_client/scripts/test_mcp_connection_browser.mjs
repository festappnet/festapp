#!/usr/bin/env node
// Isolated real Chromium, synthetic identity and broker; never production OAuth.
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer } from 'vite';
const execute = promisify(execFile);
const temporary = await mkdtemp(path.join(tmpdir(),'festapp-mcp-browser-'));
const config = path.join(temporary,'browser.json');
await writeFile(config,JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false}));
const session = `mcp-consent-${process.pid}`;
let server;
async function browser(...args) {
    const { stdout } = await execute('agent-browser',['--config',config,'--headed','false','--session',session,'--json',...args],{timeout:30000,env:{...process.env,AGENT_BROWSER_CONFIG:config,AGENT_BROWSER_PLUGINS:'[]'}});
    const result=JSON.parse(stdout); assert.equal(result.success,true,result.error); return result.data;
}
const evaluate=async source=>(await browser('eval',source)).result;
try {
    server=await createServer({configFile:false,root:path.resolve(import.meta.dirname,'..'),logLevel:'error',server:{host:'127.0.0.1',port:0,strictPort:true},plugins:[{name:'mcp-translations',configureServer(vite){vite.middlewares.use(async(req,res,next)=>{
        if(req.url==='/assets/translations/cs.json'){res.setHeader('content-type','application/json');res.end(await readFile(new URL('../../assets/translations/cs.json',import.meta.url)));return;} next();
    });}}]});
    await server.listen();
    await browser('open',`http://127.0.0.1:${server.httpServer.address().port}/tests/fixtures/mcp/index.html`);
    await browser('wait','--fn','window.consentFixture?.ready === true');
    await browser('set','viewport','1280','1000');
    await browser('snapshot','-i');
    await browser('click','input[data-occasion="99"]');
    await browser('snapshot','-i');
    assert.equal(await evaluate('document.querySelector("[data-select-all]").indeterminate'),true);
    await browser('click','input[data-select-all]');
    await browser('snapshot','-i');
    assert.deepEqual(await evaluate('consentFixture.read().selected'),[99,100]);
    assert.equal(await evaluate('consentFixture.read().operations.length'),1);
    await browser('click','input[data-select-all]');
    await browser('snapshot','-i');
    assert.equal(await evaluate('consentFixture.read().selected.length'),0);
    await browser('click','input[data-select-all]');
    await browser('snapshot','-i');
    assert.deepEqual(await evaluate('consentFixture.read().selected'),[99,100]);
    await browser('find','role','button','click','--name','Povolit a propojit');
    await browser('wait','--fn','window.consentFixture.read().state === "connected"');
    assert.deepEqual(await evaluate('consentFixture.read().operations.map(o=>o.operation)'),['details','approve','status']);
    assert.deepEqual(await evaluate('consentFixture.read().operations[1].access.occasionIds'),[99,100]);
    assert.equal(await evaluate('consentFixture.read().openerIsNull'),true);
    assert.equal(await evaluate('consentFixture.read().popupClosed'),true);
    assert.equal(await evaluate('performance.getEntriesByType("resource").some(r=>/flutter|main\\.dart|canvaskit/.test(r.name))'),false);
    console.log('mcp-consent-browser: pass (real JS controls; synthetic auth/broker; no Flutter runtime)');
} finally { await browser('close').catch(()=>{}); await server?.close(); await rm(temporary,{recursive:true,force:true}); }

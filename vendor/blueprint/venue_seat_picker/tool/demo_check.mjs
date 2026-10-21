import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
const require=createRequire(new URL('../web/package.json',import.meta.url));
const {chromium}=require('playwright');
const [base,kit]=process.argv.slice(2);
const report=path.join(kit,'report');await mkdir(report,{recursive:true});
const browser=await chromium.launch({headless:true});
const failures=[],results=[];
try{
  const context=await browser.newContext({viewport:{width:1440,height:900}});
  const page=await context.newPage();
  page.on('pageerror',e=>failures.push(e.message));
  await page.goto(`${base}/flutter/`);
  await page.waitForSelector('flutter-view',{timeout:45000});
  await page.screenshot({path:path.join(report,'flutter.png')});results.push('Flutter loader created its view');
  await page.goto(`${base}/js/demo/`);
  await page.waitForFunction(()=>window.venueDemo&&window.VenueLayoutKernel);
  results.push('JS public demo and pure Dart kernel loaded');
  await page.screenshot({path:path.join(report,'js.png')});
  await context.close();
} catch(e){failures.push(e.stack);} finally{await browser.close();}
await writeFile(path.join(report,'result.json'),JSON.stringify({results,failures},null,2));
const escape=s=>s.replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
await writeFile(path.join(report,'index.html'),`<!doctype html><meta charset="utf-8"><title>Demo artifact smoke</title><h1>Demo artifact smoke</h1><pre>${escape(JSON.stringify({results,failures},null,2))}</pre><img width="720" src="flutter.png"><img width="720" src="js.png">`);
console.log(`Demo artifact smoke: ${results.length} checks, ${failures.length} failures. ${report}/index.html`);
if(failures.length)process.exitCode=1;

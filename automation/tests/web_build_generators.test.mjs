import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

test('embed generator preserves mtime on repeat and regenerates changed contracts',t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-embed-generator-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const put=(file,data)=>{const target=path.join(root,file);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,data);};
 put('automation/lib/write_if_changed.cjs',fs.readFileSync(new URL('../lib/write_if_changed.cjs',import.meta.url)));
 put('web_client/scripts/build_embed.mjs',fs.readFileSync(new URL('../../web_client/scripts/build_embed.mjs',import.meta.url)));
 put('web_client/src/embed/host.js','globalThis.consent = true; globalThis.contract = 1;\n');
 fs.symlinkSync(path.resolve('web_client/node_modules'),path.join(root,'web_client/node_modules'),'dir');
 fs.mkdirSync(path.join(root,'web_client/public'));
 const run=()=>execFileSync(process.execPath,[path.join(root,'web_client/scripts/build_embed.mjs')],{stdio:'pipe'});
 run();const target=path.join(root,'web_client/public/embed.js'),before=fs.readFileSync(target,'utf8'),mtime=fs.statSync(target).mtimeMs;
 assert.match(before,/consent = true/);
 run();assert.equal(fs.readFileSync(target,'utf8'),before);assert.equal(fs.statSync(target).mtimeMs,mtime);
 put('web_client/src/embed/host.js','globalThis.consent = true; globalThis.contract = 2;\n');run();assert.notEqual(fs.readFileSync(target,'utf8'),before);
});

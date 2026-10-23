import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {compactFlutterJavascript} from '../compact_flutter_javascript.mjs';

test('lexical compaction preserves main/deferred execution, ASI, strings, regex and legal notices',async()=>{
 const dir=await mkdtemp(path.join(tmpdir(),'festapp-js-compact-'));
 const main=`/*! Licensed fixture */\n// formatting only\nvar deferred = {};\nvar names = ['main.dart.js_1.part.js'];\nfunction evaluate() {\n const text = 'a  b';\n const regex = /a +b/;\n return [text, regex.test(text), names[0], deferred['stable-hash']()];\n}\n`;
 const chunk=`// deferred whitespace\ndeferred['stable-hash'] = function () {\n return\n  42;\n};\n`;
 const run=(a,b)=>{const c=vm.createContext({});vm.runInContext(a,c);vm.runInContext(b,c);return JSON.stringify(vm.runInContext('evaluate()',c));};
 try{await writeFile(path.join(dir,'main.dart.js'),main);await writeFile(path.join(dir,'main.dart.js_1.part.js'),chunk);await writeFile(path.join(dir,'unrelated.js'),'// keep');
 const result=await compactFlutterJavascript(dir),a=await readFile(path.join(dir,'main.dart.js'),'utf8'),b=await readFile(path.join(dir,'main.dart.js_1.part.js'),'utf8');
 assert.equal(result.files,2);assert(result.savedBytes>0);assert.equal(run(a,b),run(main,chunk));assert(a.includes('Licensed fixture'));assert(a.includes('main.dart.js_1.part.js'));assert(b.includes('stable-hash'));assert.equal(await readFile(path.join(dir,'unrelated.js'),'utf8'),'// keep');
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('missing main or unparseable deferred library fails before changing any executable',async()=>{
 const dir=await mkdtemp(path.join(tmpdir(),'festapp-js-compact-'));
 try{await assert.rejects(compactFlutterJavascript(dir),/Missing compiled/);await writeFile(path.join(dir,'main.dart.js'),'var answer = 42;\n');await writeFile(path.join(dir,'main.dart.js_1.part.js'),'function {');await assert.rejects(compactFlutterJavascript(dir));assert.equal(await readFile(path.join(dir,'main.dart.js'),'utf8'),'var answer = 42;\n');}finally{await rm(dir,{recursive:true,force:true});}
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const script=fileURLToPath(new URL('../scripts/package.mjs',import.meta.url));

test('deployment archive includes only sealed public assets and refuses changed inputs', async () => {
  const directory=await mkdtemp(join(tmpdir(),'festapp-wix-package-'));
  try {
    await mkdir(join(directory,'dist'));
    await mkdir(join(directory,'.private'));
    await writeFile(join(directory,'.private','account.json'),'DO NOT SHIP');
    await writeFile(join(directory,'dist','unexpected.txt'),'DO NOT SHIP');
    const code='customElements.define("example-widget",class extends HTMLElement{});';
    await writeFile(join(directory,'dist','widget.js'),code);
    const manifest={version:'0.1.0',files:{'widget.js':createHash('sha256').update(code).digest('hex')}};
    await writeFile(join(directory,'dist','manifest.json'),JSON.stringify(manifest));
    execFileSync(process.execPath,[script],{cwd:directory,stdio:'pipe'});
    const archive=join(directory,'artifacts','vstupenky-online-wix-0.1.0.zip');
    assert.deepEqual(execFileSync('unzip',['-Z1',archive],{encoding:'utf8'}).trim().split('\n'),['manifest.json','widget.js']);
    const hash=createHash('sha256').update(await readFile(archive)).digest('hex');
    assert.equal(await readFile(`${archive}.sha256`,'utf8'),`${hash}  vstupenky-online-wix-0.1.0.zip\n`);
    await writeFile(join(directory,'dist','widget.js'),'tampered');
    assert.throws(()=>execFileSync(process.execPath,[script],{cwd:directory,stdio:'pipe'}),/Command failed/);
    assert.equal(createHash('sha256').update(await readFile(archive)).digest('hex'),hash);
    manifest.files={'../private':hash};
    await writeFile(join(directory,'dist','manifest.json'),JSON.stringify(manifest));
    assert.throws(()=>execFileSync(process.execPath,[script],{cwd:directory,stdio:'pipe'}),/Command failed/);
  } finally { await rm(directory,{recursive:true,force:true}); }
});

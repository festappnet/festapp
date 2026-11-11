import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, readdir, unlink, writeFile } from 'node:fs/promises';
import { ZXING_WASM_SHA256 } from 'zxing-wasm/reader';
const require=createRequire(import.meta.url);
const bytes=await readFile(require.resolve('zxing-wasm/reader/zxing_reader.wasm'));
if(createHash('sha256').update(bytes).digest('hex')!==ZXING_WASM_SHA256)throw new Error('QR decoder package digest mismatch');
const directory=new URL('../public/web-assets/',import.meta.url);
const filename=`zxing-reader-${ZXING_WASM_SHA256.slice(0,16)}.wasm`;
if(!process.argv.includes('--check')){
    await mkdir(directory,{recursive:true});
    for(const name of await readdir(directory))if(/^zxing-reader-[a-f0-9]+\.wasm$/.test(name)&&name!==filename)await unlink(new URL(name,directory));
    await writeFile(new URL(filename,directory),bytes);
}

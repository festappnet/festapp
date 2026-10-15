import fs from 'node:fs';import path from 'node:path';import zlib from 'node:zlib';
const root='/tmp/festapp-bundle-audit-20261015';const summaries=[];
for(const variant of process.argv.slice(2)){
 const dir=path.join(root,variant);const files=fs.readdirSync(dir).filter(n=>/^main\.dart\.js(?:_\d+\.part\.js)?$/.test(n)).sort();
 const rows=files.map(name=>{const bytes=fs.readFileSync(path.join(dir,name));return {name,raw:bytes.length,brotliQ9:zlib.brotliCompressSync(bytes,{params:{[zlib.constants.BROTLI_PARAM_QUALITY]:9}}).length};});
 summaries.push({variant,files:rows});
}
fs.writeFileSync(path.join(root,'size-comparison.json'),JSON.stringify(summaries,null,2)+'\n');console.log(JSON.stringify(summaries));

// pnpm --dir web_client install --frozen-lockfile before this local macOS check.
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
const jsQR=createRequire(new URL('../../web_client/package.json',import.meta.url))('jsqr');
const out=resolve(process.argv[2]);
const cases=JSON.parse(readFileSync(join(out,'contexts.json'),'utf8'));
const temp=mkdtempSync(join(tmpdir(),'ticket-qr-'));
const proof=[];
try{
 for(const item of cases)for(const kind of ['canvas','pdf']){
  const file=join(out,`${item.name}-${kind}.png`),bmp=join(temp,'image.bmp');
  execFileSync('sips',['-s','format','bmp',file,'--out',bmp],{stdio:'ignore'});
  const b=readFileSync(bmp),offset=b.readUInt32LE(10),width=b.readInt32LE(18),signedHeight=b.readInt32LE(22),height=Math.abs(signedHeight),bits=b.readUInt16LE(28);
  if(![24,32].includes(bits))throw Error('Unexpected BMP pixel format');
  const stride=Math.ceil(width*bits/32)*4,data=new Uint8ClampedArray(width*height*4);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
   const src=offset+(signedHeight<0?y:height-y-1)*stride+x*(bits/8),dst=(y*width+x)*4;
   data[dst]=b[src+2];data[dst+1]=b[src+1];data[dst+2]=b[src];data[dst+3]=255;
  }
  const qr=jsQR(data,width,height);
  const expected=item.reply.scenarios.normal.qr;
  if(qr?.data!==expected)throw Error(`${item.name}/${kind}: ${qr?.data??'QR not decoded'}`);
  proof.push({scene:item.name,kind,payload:qr.data});
 }
 writeFileSync(join(out,'qr-proof.json'),JSON.stringify(proof,null,2)+'\n');
 console.log(`${proof.length} raster QR codes decode to the canonical synthetic payload`);
}finally{rmSync(temp,{recursive:true,force:true});}

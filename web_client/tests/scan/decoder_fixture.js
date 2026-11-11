import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import QRCode from 'qrcode';
import {prepareQRDecoder} from '../../src/components/scan/scanner_codes.js';
const require=createRequire(import.meta.url);
await prepareQRDecoder({wasmBinary:readFileSync(require.resolve('zxing-wasm/reader/zxing_reader.wasm'))});

export function qrFrame({scale=3,width=960,height=540,angle=0,contrast=235,inverted=false,blur=false}={}){
 const data=new Uint8ClampedArray(width*height*4),background=inverted?0:235,foreground=inverted?235:235-contrast;
 for(let i=0;i<data.length;i+=4){data[i]=data[i+1]=data[i+2]=background;data[i+3]=255;}
 const text='TEST-ENTRY-A',qr=QRCode.create(text),size=qr.modules.size*scale,cx=width/2,cy=height/2;
 for(let y=Math.floor(cy-size);y<cy+size;y++)for(let x=Math.floor(cx-size);x<cx+size;x++){
  if(x<0||x>=width||y<0||y>=height)continue;
  const dx=x+.5-cx,dy=y+.5-cy,u=Math.floor((dx*Math.cos(angle)+dy*Math.sin(angle)+size/2)/scale),v=Math.floor((-dx*Math.sin(angle)+dy*Math.cos(angle)+size/2)/scale);
  if(u>=0&&v>=0&&u<qr.modules.size&&v<qr.modules.size&&qr.modules.get(v,u)){const i=(y*width+x)*4;data[i]=data[i+1]=data[i+2]=foreground;}
 }
 if(blur){const copy=data.slice();for(let y=1;y<height-1;y++)for(let x=1;x<width-1;x++){let sum=0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)sum+=copy[((y+dy)*width+x+dx)*4]*(dx===0?2:1)*(dy===0?2:1);const i=(y*width+x)*4;data[i]=data[i+1]=data[i+2]=Math.round(sum/16);}}
 return {data,width,height,text};
}

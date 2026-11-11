import test from 'node:test';
import assert from 'node:assert/strict';
import QRCode from 'qrcode';
import {qrFrame} from './decoder_fixture.js';
import { decodeQRCodes } from '../../src/components/scan/scanner_codes.js';
import { ScannerInput } from '../../src/components/scan/scanner_input.js';
function frame(symbols, scale=5, height=540) {
    const width=960,data=new Uint8ClampedArray(width*height*4).fill(255);
    symbols.forEach((symbol,n)=>{
        const qr=QRCode.create(symbol),margin=4,size=(qr.modules.size+2*margin)*scale;
        const angle=[0,Math.PI/6,-Math.PI/8][n%3],cx=155+n*310,cy=height/2;
        for(let y=cy-size;y<cy+size;y++)for(let x=cx-size;x<cx+size;x++){
            const dx=x-cx,dy=y-cy,u=Math.floor((dx*Math.cos(angle)+dy*Math.sin(angle)+size/2)/scale)-margin,v=Math.floor((-dx*Math.sin(angle)+dy*Math.cos(angle)+size/2)/scale)-margin;
            if(x>=0&&x<width&&y>=0&&y<height&&u>=0&&v>=0&&u<qr.modules.size&&v<qr.modules.size&&qr.modules.get(v,u)){
                const i=(y*width+x)*4;data[i]=data[i+1]=data[i+2]=0;
            }
        }
    });return {data,width,height};
}
test('three real QR symbols in one frame decode independently, including rotated tickets',async()=>{
    const image=frame(['TICKET-A','TICKET-B','TICKET-C']),before=image.data.slice();
    const result=await decodeQRCodes(image.data,image.width,image.height);
    assert.deepEqual(new Set(result.map(c=>c.value)),new Set(['TICKET-A','TICKET-B','TICKET-C']));
    assert.deepEqual(image.data,before,'masking must not mutate the camera frame');
});
test('duplicate QR payloads are returned once without hiding a different neighbouring ticket',async()=>{
    const image=frame(['TICKET-A','TICKET-A','TICKET-B']);
    assert.deepEqual(new Set((await decodeQRCodes(image.data,image.width,image.height)).map(c=>c.value)),new Set(['TICKET-A','TICKET-B']));
});
test('two visible QR codes are handled one at a time without suppressing an unseen second ticket',async()=>{
 const image=frame(['TICKET-A','TICKET-B']),singles=[];
 const input=new ScannerInput(code=>singles.push(code));
 input.video={videoWidth:image.width,videoHeight:image.height};input.canvas={};input.decode=decodeQRCodes;
 input.context={drawImage(){},getImageData:()=>image};
 await input.frame();await input.frame();assert.equal(singles.length,1);assert.equal(input.paused,true);
 input.paused=false;await input.frame();assert.equal(singles.length,2);assert.notEqual(singles[0],singles[1]);
 input.paused=false;await input.frame();assert.equal(singles.length,2,'visible completed codes remain suppressed');
 input.allowSame();await input.frame();assert.equal(singles.length,3,'an explicit next allows the same code again');
});

test('large adjacent ticket codes remain readable in a wide camera frame',async()=>{
    const symbols=['SCANNER-1281-95','SCANNER-1281-94','SCANNER-1281-93'],image=frame(symbols,9,360);
    assert.deepEqual(new Set((await decodeQRCodes(image.data,image.width,image.height)).map(c=>c.value)),new Set(symbols));
});

for (const inverted of [true, false]) test(`PDF ticket QR polarity: inverted=${inverted}`,async()=>{
    const symbol='X3485A9H2F',image=frame([symbol]);
    if(inverted)for(let i=0;i<image.data.length;i+=4)for(let c=0;c<3;c++)image.data[i+c]=255-image.data[i+c];
    assert.deepEqual((await decodeQRCodes(image.data,image.width,image.height)).map(c=>c.value),[symbol]);
});

for(const [name,options] of [
 ['tiny',{scale:1.6}],['low-contrast',{contrast:70}],['blurred-small',{scale:2.4,blur:true}],
 ['rotated-small',{scale:2.3,angle:Math.PI/9}],['distant-HD',{width:1920,height:1080,scale:2.7}],
])test(`reader detects ${name} ticket without enlarged QR`,async()=>{
 const image=qrFrame(options);
 assert.deepEqual((await decodeQRCodes(image.data,image.width,image.height)).map(code=>code.value),[image.text]);
});

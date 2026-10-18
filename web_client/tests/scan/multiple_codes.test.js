import test from 'node:test';
import assert from 'node:assert/strict';
import QRCode from 'qrcode';
import jsQR from 'jsqr';
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
test('three real QR symbols in one frame decode independently, including rotated tickets',()=>{
    const image=frame(['TICKET-A','TICKET-B','TICKET-C']),before=image.data.slice();
    const result=decodeQRCodes(image.data,image.width,image.height,jsQR);
    assert.deepEqual(new Set(result.map(c=>c.value)),new Set(['TICKET-A','TICKET-B','TICKET-C']));
    assert.deepEqual(image.data,before,'masking must not mutate the camera frame');
});
test('duplicate QR payloads are returned once without hiding a different neighbouring ticket',()=>{
    const image=frame(['TICKET-A','TICKET-A','TICKET-B']);
    assert.deepEqual(new Set(decodeQRCodes(image.data,image.width,image.height,jsQR).map(c=>c.value)),new Set(['TICKET-A','TICKET-B']));
});
test('camera dispatches one group, suppresses repeated visible tickets and re-arms after they leave',()=>{
    const image=frame(['TICKET-A','TICKET-B']),groups=[],singles=[];
    const input=new ScannerInput(code=>singles.push(code),{onCodes:codes=>groups.push(codes)});
    input.video={videoWidth:image.width,videoHeight:image.height};input.canvas={};input.decode=jsQR;
    input.context={drawImage(){},getImageData:()=>image};
    input.frame();input.frame();assert.equal(groups.length,1);assert.equal(singles.length,0);
    input.paused=false;input.frame();assert.equal(groups.length,1);
    input.context.getImageData=()=>({...image,data:new Uint8ClampedArray(image.data.length).fill(255)});input.frame();
    input.context.getImageData=()=>image;input.frame();assert.equal(groups.length,2);
});

test('large adjacent ticket codes remain readable in a wide camera frame',()=>{
    const symbols=['SCANNER-1281-95','SCANNER-1281-94','SCANNER-1281-93'],image=frame(symbols,9,360);
    assert.deepEqual(new Set(decodeQRCodes(image.data,image.width,image.height,jsQR).map(c=>c.value)),new Set(symbols));
});

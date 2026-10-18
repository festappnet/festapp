import test from 'node:test';import assert from 'node:assert/strict';import QRCode from 'qrcode';import jsQR from 'jsqr';import { ScannerInput } from '../../src/components/scan/scanner_input.js';
test('C01 local decoder reads QR pixels without BarcodeDetector or a CDN',()=>{const text='SCANNER-OFFLINE-LOCAL',qr=QRCode.create(text),scale=4,margin=4,width=(qr.modules.size+2*margin)*scale,pixels=new Uint8ClampedArray(width*width*4).fill(255);for(let y=0;y<qr.modules.size;y++)for(let x=0;x<qr.modules.size;x++)if(qr.modules.get(y,x))for(let dy=0;dy<scale;dy++)for(let dx=0;dx<scale;dx++){const i=(((y+margin)*scale+dy)*width+(x+margin)*scale+dx)*4;pixels[i]=pixels[i+1]=pixels[i+2]=0;}assert.equal(jsQR(pixels,width,width).data,text);});
test('C02 repeated detections pause input until deliberate next; dispose stops tracks',()=>{const codes=[];const input=new ScannerInput(code=>codes.push(code));input.accept('A');input.accept('A');input.accept('B');assert.deepEqual(codes,['A']);let stopped=false;input.stream={getTracks:()=>[{stop:()=>{stopped=true;}}]};input.dispose();assert.equal(stopped,true);assert.equal(input.stream,null);});

test('review pauses decoding while keeping the live stream; default pause still releases it',()=>{
    const input=new ScannerInput(()=>assert.fail('review cannot dispatch a new ticket'));
    let stopped=0;input.stream={getTracks:()=>[{stop(){stopped++;}}]};
    input.video={videoWidth:640};input.context={drawImage(){assert.fail('review cannot decode frames');}};
    input.pause({keepStream:true});input.frame();
    assert.equal(stopped,0);assert.ok(input.stream);assert.equal(input.paused,true);
    input.pause();assert.equal(stopped,1);assert.equal(input.stream,null);
});

test('continuous scanner accepts further tickets without pausing and suppresses duplicate codes',()=>{
    const codes=[],input=new ScannerInput(code=>codes.push(code),{continuous:true});
    input.accept('A');input.accept('A');input.accept('B');
    assert.deepEqual(codes,['A','B']);assert.equal(input.paused,false);
    input.pause({keepStream:true});input.accept('C');assert.deepEqual(codes,['A','B']);
});

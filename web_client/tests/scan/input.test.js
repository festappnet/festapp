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

test('camera worker keeps decoding off the UI thread, bounds its queue and fences stopped results',async t=>{
 const previous={navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),document:globalThis.document,Worker:globalThis.Worker};
 const workers=[],messages=[],codes=[];let trackStops=0;
 const stream={getTracks:()=>[{stop(){trackStops++;}}]};
 const context={drawImage(){},getImageData(){return {data:new Uint8ClampedArray(16*16*4)};}};
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{mediaDevices:{getUserMedia:async()=>stream}}});
 globalThis.document={createElement:()=>({getContext:()=>context})};
 globalThis.Worker=class {
  constructor(url,options){assert.match(url.pathname,/scanner_decoder_worker\.js$/);assert.equal(options.type,'module');workers.push(this);}
  postMessage(message,transfers){messages.push(message);assert.equal(transfers[0],message.pixels.buffer);}
  terminate(){this.terminated=true;}
 };
 const input=new ScannerInput(code=>codes.push(code),{continuous:true});
 t.after(()=>{input.dispose();Object.defineProperty(globalThis,'navigator',previous.navigator);globalThis.document=previous.document;if(previous.Worker===undefined)delete globalThis.Worker;else globalThis.Worker=previous.Worker;});
 await input.start({videoWidth:16,videoHeight:16,async play(){}});
 const worker=workers[0];assert.ok(worker);
 input.decode=()=>assert.fail('worker-enabled camera must not run jsQR on the UI thread');
 input.frame();input.frame();assert.equal(messages.length,1,'busy worker must not accumulate camera frames');
 worker.onmessage({data:{codes:[{value:'SAME'}],done:false}});assert.deepEqual(codes,['SAME']);
 input.frame();assert.equal(messages.length,1,'progress must keep the frame in flight until full recovery finishes');
 worker.onmessage({data:{codes:[{value:'SAME'}],done:true}});
 input.frame();worker.onmessage({data:{codes:[{value:'SAME'}]}});assert.deepEqual(codes,['SAME']);
 input.allowSame();input.frame();worker.onmessage({data:{codes:[{value:'SAME'}]}});assert.deepEqual(codes,['SAME','SAME']);
 input.pause({keepStream:true});worker.onmessage({data:{codes:[{value:'PAUSED'}]}});assert.deepEqual(codes,['SAME','SAME']);
 input.stop();assert.equal(worker.terminated,true);assert.equal(trackStops,1);
 worker.onmessage({data:{codes:[{value:'STALE'}]}});assert.deepEqual(codes,['SAME','SAME']);
});

test('worker startup failure retains the local offline decoder',async t=>{
 const previous={navigator:Object.getOwnPropertyDescriptor(globalThis,'navigator'),document:globalThis.document,Worker:globalThis.Worker};
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{mediaDevices:{getUserMedia:async()=>({getTracks:()=>[]})}}});
 globalThis.document={createElement:()=>({getContext:()=>({})})};
 const workers=[];globalThis.Worker=class {constructor(){workers.push(this);}terminate(){this.terminated=true;}};
 const input=new ScannerInput(()=>{});
 t.after(()=>{input.dispose();Object.defineProperty(globalThis,'navigator',previous.navigator);globalThis.document=previous.document;if(previous.Worker===undefined)delete globalThis.Worker;else globalThis.Worker=previous.Worker;});
 await input.start({async play(){}});assert.equal(typeof input.decode,'function');
 workers[0].onerror({preventDefault(){}});
 assert.equal(input.decoderWorker,null);assert.equal(workers[0].terminated,true);assert.equal(typeof input.decode,'function');assert.ok(input.stream);
});

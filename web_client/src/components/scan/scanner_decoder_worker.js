import { decodeQRCodes, prepareQRDecoder } from './scanner_codes.js';

const ready=prepareQRDecoder();
ready.catch(()=>{}); // A failed initialization is reported to the camera owner below.
self.onmessage=async({data:{pixels,width,height}})=>{
    try {
        await ready;
        self.postMessage({codes:await decodeQRCodes(pixels,width,height)});
    } catch {
        self.postMessage({error:'camera_unavailable'});
    }
};

import { prepareZXingModule, readBarcodes, ZXING_WASM_SHA256 } from 'zxing-wasm/reader';

export const qrDecoderAsset = `/web-assets/zxing-reader-${ZXING_WASM_SHA256.slice(0,16)}.wasm`;
let initialization;

// The pinned engine is served by this application, including its offline shell.
export function prepareQRDecoder(overrides={}) {
    initialization ??= (async()=>{
        // The content-addressed engine is identical across shell generations.
        // A fresh dedicated worker cannot answer the PWA window-version handshake,
        // so read its installed binary directly before making a network request.
        let wasmBinary=overrides.wasmBinary;
        if(!wasmBinary){
            let response;
            try { response=await globalThis.caches?.match(qrDecoderAsset); } catch { /* Cache storage is optional outside the installed PWA. */ }
            response ??= await fetch(qrDecoderAsset);
            if(!response.ok)throw new Error('camera_unavailable');
            wasmBinary=await response.arrayBuffer();
        }
        return prepareZXingModule({
            overrides:{locateFile:()=>qrDecoderAsset,...overrides,wasmBinary},
            fireImmediately:true,
        });
    })().catch(error=>{initialization=null;throw error;});
    return initialization;
}

export async function decodeQRCodes(pixels,width,height) {
    await prepareQRDecoder();
    const results=await readBarcodes({data:pixels,width,height},{
        formats:['QRCode'],tryHarder:true,tryRotate:true,tryInvert:true,
        tryDownscale:true,maxNumberOfSymbols:12,
    });
    const seen=new Set();
    return results.filter(code=>code.isValid && code.text && !seen.has(code.text) && seen.add(code.text))
        .map(code=>({value:code.text,x:code.position.topLeft.x,y:code.position.topLeft.y}))
        .sort((a,b)=>a.y-b.y||a.x-b.x);
}

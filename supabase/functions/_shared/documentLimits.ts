import { AuthError } from './authError.ts';
export function documentLimits(data: any) {
  const rules=data?.abuseLimits;
  const read=(key:string)=>{
    const value=rules?.[key];
    if(!Number.isSafeInteger(value)||value<=0)throw new AuthError('Document policy unavailable',503);
    return value as number;
  };
  return {inputBytes:read('document.input.bytes'),assetBytes:read('document.asset.bytes'),outputBytes:read('document.output.bytes'),pages:read('document.output.pages')};
}
export function boundDocumentInput(data:unknown,maxBytes:number) {
  if(new TextEncoder().encode(JSON.stringify(data)).byteLength>maxBytes)throw new AuthError('Document input too large',429);
}
export function boundDocumentOutput(bytes:Uint8Array,pages:number,limits:ReturnType<typeof documentLimits>) {
  if(bytes.byteLength>limits.outputBytes||pages>limits.pages)throw new AuthError('Document output too large',429);
}

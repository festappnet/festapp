const encoder=new TextEncoder();
export async function walletHash(value:string) {
 return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(value))),b=>b.toString(16).padStart(2,'0')).join('');
}

import {assert,assertEquals,assertNotEquals,assertRejects,assertThrows} from 'jsr:@std/assert@1';
import {unzipSync} from 'npm:fflate@0.8.3';
import {AppleWallet,appleWalletDocument,appleWalletSerial,validateAppleCredentials,type AppleWalletCredentials} from './appleWallet.ts';
import {issueAppleTicketWallet,appleWalletConnector} from './wallet/connectors/apple.ts';
import {issueTicketWallet,googleWalletConnector} from './wallet/connectors/google.ts';
import {WalletRegistry} from './wallet/registry.ts';
import {walletHandler} from '../ticket-wallet/handler.ts';
import {sealEmail} from './emailPayload.ts';
import {reconcileAppleTicketWallet} from './appleWalletUpdates.ts';
import type {GoogleWallet} from './googleWallet.ts';
const credentials={passTypeIdentifier:'pass.net.festapp.test',teamIdentifier:'TESTTEAM01'} as AppleWalletCredentials;
const identity={environment:'test',organization:1,occasion:2,ticketId:3};
const projection:any={branding:{APP_NAME:'Ukázkový portál',DEFAULT_URL:'https://tenant.invalid'},state:'ACTIVE',ticket:{ticket_symbol:'EXACT-QR-č',order_product_ticket:[{spot_title:'12',spot_group_title:'Stůl 4',product:{title:'Vstupné'}}]},occasion:{title:'Večer hudby',start_time:'2027-03-28T18:00:00Z',end_time:'2027-03-28T22:00:00Z',data:{timezone:'Europe/Prague',place_name:'Kulturní dům'}}};
const resolved={...identity,webOrigin:'https://tenant.invalid',providers:{google:false,apple:true},applePassTypeIdentifier:credentials.passTypeIdentifier,appleTeamIdentifier:credentials.teamIdentifier,projection};

Deno.test('Apple serial isolates backend, organization, event and ticket; QR and native fields retain canonical values',async()=>{
 const serial=await appleWalletSerial(identity);
 for(const changed of [{environment:'other'},{organization:4},{occasion:4},{ticketId:4}])assertNotEquals(await appleWalletSerial({...identity,...changed}),serial);
 assertEquals(await appleWalletSerial({...identity}),serial);
 const doc=appleWalletDocument(serial,projection,credentials);
 assertEquals(doc.barcodes[0].message,'EXACT-QR-č');assertEquals(doc.passTypeIdentifier,credentials.passTypeIdentifier);
 assertEquals(doc.eventTicket.auxiliaryFields.map(f=>f.value),['Stůl 4','12','Vstupné']);
 assert(doc.eventTicket.secondaryFields[0].value.includes('20:00')); // Prague DST offset.
 assertEquals(doc.voided,false);
 assertEquals(appleWalletDocument(serial,{...projection,state:'COMPLETED'},credentials).voided,true);
 for(const state of ['INACTIVE','EXPIRED'])assertEquals(appleWalletDocument(serial,{...projection,state} as any,credentials).voided,true);
});
Deno.test('Apple issuance rejects invalid scope/payment/readiness, changed identity and concurrent storno without Google calls',async()=>{
 let signed=0;const apple={credentials,issue:async()=>{signed++;return new Uint8Array([1,2]);}} as unknown as AppleWallet;
 for(const value of [null,{...resolved,webOrigin:'https://foreign.invalid'},{...resolved,providers:{apple:false}},{...resolved,projection:{state:'INACTIVE'}},{...resolved,projection:{state:'EXPIRED'}}])assertEquals(await issueAppleTicketWallet('a'.repeat(64),'ip',resolved.webOrigin,async()=>value,apple),null);
 assertEquals(signed,0);
 await assertRejects(()=>issueAppleTicketWallet('a'.repeat(64),'ip',resolved.webOrigin,async()=>({...resolved,appleTeamIdentifier:'OTHERTEAM1'}),apple));
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 const authToken='c'.repeat(64);
 const context={serial:await appleWalletSerial(identity),passTypeIdentifier:credentials.passTypeIdentifier,authHash:await (await import('./wallet/identity.ts')).walletHash(authToken),authSealed:await sealEmail({purpose:'apple_wallet_auth',serial:await appleWalletSerial(identity),passTypeIdentifier:credentials.passTypeIdentifier,token:authToken})};
 let calls=0;
 assertEquals(await issueAppleTicketWallet('a'.repeat(64),'ip',resolved.webOrigin,async name=>{if(name==='register_apple_ticket_wallet')return context;assertEquals(name,'resolve_ticket_wallet');return ++calls===1?resolved:{...resolved,projection:{state:'INACTIVE'}};},apple),null);
 assertEquals(signed,1);
 await assertRejects(()=>issueTicketWallet('a'.repeat(64),'ip',resolved.webOrigin,async()=>resolved,{} as GoogleWallet));Deno.env.delete('EMAIL_PAYLOAD_KEY');
});
Deno.test('native Apple POST returns pkpass MIME and attachment without Google credentials; malformed inputs never sign',async()=>{
 let signed=0;const bytes=new Uint8Array([80,75,3,4]);
 const apple={credentials,issue:async()=>{signed++;return bytes;}} as unknown as AppleWallet;
 Deno.env.set('EMAIL_PAYLOAD_KEY',btoa('a'.repeat(32)));
 const authToken='c'.repeat(64);const serial=await appleWalletSerial(identity);
 const context={serial,passTypeIdentifier:credentials.passTypeIdentifier,authHash:await (await import('./wallet/identity.ts')).walletHash(authToken),authSealed:await sealEmail({purpose:'apple_wallet_auth',serial,passTypeIdentifier:credentials.passTypeIdentifier,token:authToken})};
 const handler=walletHandler(new WalletRegistry([['apple',()=>appleWalletConnector(async name=>name==='register_apple_ticket_wallet'?context:resolved,async()=>apple)]],'apple'),[resolved.webOrigin]);
 const response=await handler(new Request('https://backend.invalid',{method:'POST',headers:{origin:resolved.webOrigin,'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:'a'.repeat(64),provider:'apple'})}));
 assertEquals(response.status,200);assertEquals(response.headers.get('content-type'),'application/vnd.apple.pkpass');assert(response.headers.get('content-disposition')?.includes('ticket.pkpass'));assertEquals(new Uint8Array(await response.arrayBuffer()),bytes);assertEquals(signed,1);
 for(const body of ['token='+ 'a'.repeat(64)+'&provider=apple&token='+ 'b'.repeat(64),'token='+ 'a'.repeat(64)+'&provider=google','token='+ 'a'.repeat(64)+'&provider=apple&ticketId=3']){
  const res=await handler(new Request('https://backend.invalid',{method:'POST',headers:{origin:resolved.webOrigin,'Content-Type':'application/x-www-form-urlencoded'},body}));assertEquals(res.status,400);
 }
 assertEquals(signed,1);Deno.env.delete('EMAIL_PAYLOAD_KEY');
});
Deno.test('signed Apple ZIP has valid manifest hashes and independently verified detached CMS signature',async()=>{
 const dir=await Deno.makeTempDir({prefix:'festapp-wallet-signing-'});
 const run=async(args:string[])=>{const result=await new Deno.Command('openssl',{args,cwd:dir,stdout:'piped',stderr:'piped'}).output();assertEquals(result.code,0,'OpenSSL fixture/signature check failed');};
 try {
  await run(['req','-x509','-newkey','rsa:2048','-nodes','-keyout','wwdr.key','-out','wwdr.pem','-days','1','-subj','/CN=Festapp disposable WWDR','-addext','basicConstraints=critical,CA:TRUE']);
  await run(['req','-new','-newkey','rsa:2048','-nodes','-keyout','signer.key','-out','signer.csr','-subj','/UID=pass.net.festapp.test/OU=TESTTEAM01/CN=Festapp disposable pass']);
  await run(['x509','-req','-in','signer.csr','-CA','wwdr.pem','-CAkey','wwdr.key','-set_serial','2','-out','signer.pem','-days','1']);
  const creds={...credentials,signerCert:await Deno.readTextFile(dir+'/signer.pem'),signerKey:await Deno.readTextFile(dir+'/signer.key'),wwdr:await Deno.readTextFile(dir+'/wwdr.pem')};
  validateAppleCredentials(creds);
  assertThrows(()=>validateAppleCredentials({...creds,teamIdentifier:'OTHERTEAM1'}));
  assertThrows(()=>validateAppleCredentials({...creds,passTypeIdentifier:'pass.other'}));
  assertThrows(()=>validateAppleCredentials({...creds,signerKey:creds.wwdr}));
  assertThrows(()=>validateAppleCredentials(creds,Date.now()+2*86400000));
  const icons:Record<string,Uint8Array>={};for(const name of ['icon.png','icon@2x.png','icon@3x.png'])icons[name]=await Deno.readFile(new URL('./ticket-assets/apple-wallet/'+name,import.meta.url));
  const apple=new AppleWallet(creds,icons,()=>{throw new Error('unexpected external I/O');},'https://api.festapp.net/functions/v1/apple-wallet');
  const files=unzipSync(await apple.issue(identity,projection,{authenticationToken:'e'.repeat(64)}));
  const decode=(v:Uint8Array)=>new TextDecoder().decode(v);
  const pass=JSON.parse(decode(files['pass.json']));assertEquals(pass.barcodes[0].message,projection.ticket.ticket_symbol);assertEquals(pass.serialNumber,await appleWalletSerial(identity));
  assertEquals(pass.webServiceURL,apple.webServiceURL);assertEquals(pass.authenticationToken,'e'.repeat(64));
  const manifest=JSON.parse(decode(files['manifest.json']));
  for(const [name,hash] of Object.entries(manifest))assertEquals(Array.from(new Uint8Array(await crypto.subtle.digest('SHA-1',files[name])),b=>b.toString(16).padStart(2,'0')).join(''),hash);
  assert(files['icon.png']&&files['icon@2x.png']&&files['icon@3x.png']);
  await Deno.writeFile(dir+'/signature',files.signature);await Deno.writeFile(dir+'/manifest.json',files['manifest.json']);
  await run(['cms','-verify','-binary','-inform','DER','-in','signature','-content','manifest.json','-noverify','-out','verified']);
 }finally{await Deno.remove(dir,{recursive:true});}
});
Deno.test('Apple worker fences notification receipts, removes invalid tokens and preserves retries after transport failure',async()=>{
 const finishes:any[]=[];const receipts:any[]=[];let next=0;
 const claims=[{ticketId:1,lease:'a',passTypeIdentifier:credentials.passTypeIdentifier,teamIdentifier:credentials.teamIdentifier,updateTag:'9'},{ticketId:2,lease:'b',passTypeIdentifier:credentials.passTypeIdentifier,teamIdentifier:credentials.teamIdentifier,updateTag:'10'}];
 const rpc=async(name:string,p:any)=>{if(name==='claim_apple_ticket_wallet')return claims[next++]??null;if(name==='apple_wallet_push_targets')return [{pushToken:p.p_ticket===1?'bad':'retry'}];if(name==='finish_apple_wallet_push'){receipts.push(p);return true;}if(name==='finish_apple_ticket_wallet'){finishes.push(p);return true;}};
 const apple={credentials,push:async(token:string)=>{if(token==='retry')throw new Error('timeout');return 'invalid';}} as unknown as AppleWallet;
 assertEquals(await reconcileAppleTicketWallet(rpc,apple),{synced:1,failed:1});assertEquals(receipts[0].p_invalid,true);assertEquals(receipts[0].p_tag,'9');assertEquals(finishes.map(x=>x.p_ok),[true,false]);
});

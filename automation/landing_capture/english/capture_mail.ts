/** Local file transport through the canonical durable email worker. Never uses SES. */
import {drainEmails} from '../../../supabase/functions/_shared/emailDispatcher.ts';
import {renderQueuedEmail} from '../../../supabase/functions/_shared/emailRenderer.ts';
import {emailRpc} from '../../../supabase/functions/_shared/emailQueueClient.ts';
import {sealEmail,openEmail} from '../../../supabase/functions/_shared/emailPayload.ts';
import {sendEmailAttempt} from '../../../supabase/functions/_shared/emailSender.ts';
import type {PreparedEmail} from '../../../supabase/functions/_shared/emailDelivery.ts';
const out=Deno.args[0];
if(Deno.env.get('SUPABASE_URL')!=='http://127.0.0.1:57321'||!out)throw Error('Disposable English backend and capture directory required');
await Deno.mkdir(out,{recursive:true});
let count=0;
const result=await drainEmails({rpc:emailRpc,prepare:async row=>{if(row.organization!==900001)throw Error('Synthetic tenant only');try{return await renderQueuedEmail(row);}catch(error){console.error(error);throw error;}},seal:sealEmail,now:Date.now,
send:async row=>{await sendEmailAttempt(row.attempt_id,row.lease_token,{rpc:emailRpc,open:openEmail,
config:{region:'eu-central-1',accessKey:'',secretKey:'',sender:Deno.env.get('DEFAULT_EMAIL')!,transactionalSet:'local',securitySet:'local',maxBytes:30000000},
send:async(message:PreparedEmail,tags)=>{if(!message.to.endsWith('@example.invalid'))throw Error('Synthetic recipient required');const name=tags.message_id;await Deno.writeTextFile(`${out}/${name}.html`,message.html);await Deno.writeTextFile(`${out}/${name}.json`,JSON.stringify({subject:message.subject,to:message.to,attachments:message.attachments.map(a=>a.filename),transport:'local-file-capture'},null,2));for(const a of message.attachments){if(!/^[a-zA-Z0-9_.-]+\.pdf$/.test(a.filename))throw Error('Unexpected attachment');await Deno.writeFile(`${out}/${a.filename}`,Uint8Array.from(atob(a.content),c=>c.charCodeAt(0)));}count++;return `local-file-${name}`;}});}});
console.log(JSON.stringify({result,captured:count,transport:'local-file-capture'}));

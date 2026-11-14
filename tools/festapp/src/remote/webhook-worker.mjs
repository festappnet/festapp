import {validateWebhookEvent} from './webhook-events.mjs';
import { DelegatedOwner } from './delegation.mjs';
import { clientPolicy } from './client-policy.mjs';
import { connectionActive, connectionDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { READ_SCOPE } from './config.mjs';
import { Operations } from '../operations/catalog.mjs';
import { webhookBinding, webhookRpc } from '../operations/webhooks.mjs';
import { createWebhookSender } from './webhook-delivery.mjs';
import { nextWebhookAttempt, WEBHOOK_LIMITS } from './webhook-protocol.mjs';
import { check } from '../errors.mjs';

/** A server-side continuation of the original stored consent, not a new OAuth
 * token or service identity. No access credential is minted or returned. */
export function webhookDispatchOwner(config,storage,grant,{fetchImpl}={}){
    const client=clientPolicy(config,grant.clientId);
    check(connectionActive(grant)&&client?.transports?.includes('api')&&client.dataProfile!=='order-summary','FORBIDDEN');
    const owner=new DelegatedOwner(config,storage,{
        grantId:grant.id,accountId:grant.userId,clientId:grant.clientId,aud:grant.resource,
        scope:[READ_SCOPE,...(grant.permissions??[])].join(' '),
        exp:Math.floor(Math.min(connectionDeadline(grant),Date.now()+300000)/1000),
        ...(grant.proofProfile==='dpop'?{jkt:'internal-consent-continuation'}:{}),
    },{fetchImpl,transport:'api',expectedResource:grant.resource});
    check(owner.permitsOperation('webhooks.create'),'FORBIDDEN');
    return owner;
}
export function createWebhookWorker({config,storage,fetchImpl,audit=()=>{},send=createWebhookSender(),ownerForGrant}){
    let timer,active,closing=false,cursor=0;
    const controller=new AbortController();
    const ownerFor=grant=>ownerForGrant?ownerForGrant(grant):webhookDispatchOwner(config,storage,grant,{fetchImpl});
    async function one(record){
        if(closing)return;
        const grant=storage.get('Delegation',record.grantId);
        if(!connectionActive(grant))return;
        let owner;
        try{
            owner=ownerFor(grant);
            check(webhookBinding(owner)===record.binding,'FORBIDDEN');
            await owner.authorizeOperation('webhooks.create',{occasionId:record.occasionId});
            if(record.pendingCommand){
                const intent=storage.get('WebhookCommand',record.binding+':'+record.pendingCommand);
                if(intent?.phase==='pending'&&owner.permitsOperation(intent.operation))
                    await new Operations(owner).invoke(intent.operation,intent.args);
                return;
            }
            await owner.authorized(async client=>storage.runSessionExclusive('webhook-subscription:'+record.binding+':'+record.id,async()=>{
                const latest=storage.get('WebhookSubscription',record.binding+':'+record.id);
                if(!latest||latest.pendingCommand||latest.version!==record.version||latest.url!==record.url)return;
                if(record.state!=='active')return;
                const job=await webhookRpc(owner,client,record.occasionId,'claim',{subscriptionId:record.id});
                if(!job.id)return;
                const local=()=>storage.get('WebhookSubscription',record.binding+':'+record.id);
                const valid=()=>{
                    owner.current();
                    check(owner.permitsOperation('webhooks.create'),'FORBIDDEN');
                    const live=local();
                    check(live&&live.expiresAt>Date.now()&&!live.pendingCommand&&live.state==='active'&&live.version===job.version&&live.url===record.url,'FORBIDDEN');
                    return live;
                };
                const data=validateWebhookEvent(JSON.parse(job.body),record.occasionId);
                check(data.id===job.eventId&&data.source===`https://api.festapp.net/integrations/organizations/${owner.profile.organizationId}`,'FORBIDDEN');
                const current=valid();
                const retained=current.secrets.filter(k=>!k.expiresAt||k.expiresAt>Date.now());
                if(retained.length!==current.secrets.length)storage.putUntil('WebhookSubscription',record.binding+':'+record.id,{...current,secrets:retained},current.expiresAt);
                const keys=retained.map(k=>k.key);
                const outcome=await send({url:current.url,body:job.body,deliveryId:job.id,secrets:keys,signal:controller.signal,
                    beforeSend:async()=>{
                        valid();
                        const proof=await webhookRpc(owner,client,record.occasionId,'authorize',{subscriptionId:record.id,deliveryId:job.id,lease:job.lease,expectedVersion:job.version});
                        check(proof.authorized,'FORBIDDEN');valid();
                    }});
                if(closing)return; // Leave the durable lease to restart recovery.
                const due=nextWebhookAttempt({attempt:job.attempt,firstAttemptAt:Date.parse(job.firstAttemptAt),now:Math.max(Date.now(),Date.parse(job.firstAttemptAt)),retryAfterSeconds:outcome.retryAfterSeconds??0});
                const state=outcome.status>=200&&outcome.status<300?'succeeded':
                    ['destination','revoked'].includes(outcome.errorCategory)?'blocked':outcome.status===410||due===null?'exhausted':'pending';
                const completion=await webhookRpc(owner,client,record.occasionId,'complete',{subscriptionId:record.id,deliveryId:job.id,lease:job.lease,state,
                    httpStatus:outcome.status,errorCategory:outcome.errorCategory,nextDue:state==='pending'?new Date(due).toISOString():null});
                if(completion.completed&&outcome.status===410){const live=local();storage.putUntil('WebhookSubscription',record.binding+':'+record.id,{...live,state:'disabled',version:job.version+1},live.expiresAt);}
                audit({event:'webhook_attempt',outcome:state,status:outcome.status,attempt:job.attempt});
            }));
        }catch(error){
            // Never log endpoint URLs, secrets, customer data or backend messages.
            audit({event:'webhook_blocked',code:['FORBIDDEN','AUTHENTICATION_REQUIRED','INVALID_INPUT'].includes(error.code)?error.code:'UNAVAILABLE'});
        }
    }
    async function perform(){
        // Retention is the existing cron job's responsibility. Paused, disabled
        // and expired endpoints need neither polling nor an Auth refresh. Pending
        // management intents still reconcile, including a staged deletion.
        const now=Date.now();
        const rows=storage.values('WebhookSubscription').filter(r=>r.expiresAt>now&&(r.pendingCommand||r.state==='active'));
        if(!rows.length)return;
        // Round-robin bounded work keeps a large subscription set from starving.
        const selected=Array.from({length:Math.min(rows.length,WEBHOOK_LIMITS.concurrency)},(_,i)=>rows[(cursor+i)%rows.length]);
        cursor=(cursor+selected.length)%rows.length;
        await Promise.all(selected.map(one));
    }
    return {
        drain(){if(closing)return Promise.resolve();if(!active)active=perform().finally(()=>{active=undefined;});return active;},
        start(){if(timer||closing)return;timer=setInterval(()=>{void this.drain().catch(()=>audit({event:'webhook_worker_failure'}));},1000);timer.unref();},
        async close(){closing=true;clearInterval(timer);controller.abort();await active;},
    };
}

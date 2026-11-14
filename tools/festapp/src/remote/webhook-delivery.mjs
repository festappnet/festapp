import { lookup } from 'node:dns/promises';
import { request } from 'node:https';
import { BlockList, isIP } from 'node:net';
import { signWebhook, WEBHOOK_LIMITS } from './webhook-protocol.mjs';
import { check } from '../errors.mjs';

const blocked = new BlockList();
for (const [address, bits] of [['0.0.0.0',8],['10.0.0.0',8],['100.64.0.0',10],['127.0.0.0',8],['169.254.0.0',16],['172.16.0.0',12],['192.0.0.0',24],['192.0.2.0',24],['192.88.99.0',24],['192.168.0.0',16],['198.18.0.0',15],['198.51.100.0',24],['203.0.113.0',24],['224.0.0.0',4],['240.0.0.0',4]]) blocked.addSubnet(address,bits,'ipv4');
const globalV6 = new BlockList(); globalV6.addSubnet('2000::',3,'ipv6');
for (const [address,bits] of [['2001::',23],['2001:db8::',32],['2002::',16],['3fff::',20]]) blocked.addSubnet(address,bits,'ipv6');

export function publicWebhookAddress(address) {
    const family = isIP(address);
    if (!family || address.includes('%')) return false;
    return family === 4 ? !blocked.check(address,'ipv4') : globalV6.check(address,'ipv6') && !blocked.check(address,'ipv6');
}
export function validateWebhookUrl(value) {
    check(typeof value === 'string' && value.length <= 2048 && !/[\s\x00-\x1f\x7f]/.test(value),'INVALID_INPUT');
    let url; try { url = new URL(value); } catch { check(false,'INVALID_INPUT'); }
    const host = url.hostname;
    check(url.protocol === 'https:' && !url.username && !url.password && !url.hash && (!url.port || url.port === '443') &&
        !isIP(host.replace(/^\[|\]$/g,'')) && /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(host) &&
        host.includes('.') && !/(^|\.)(localhost|local|internal)$/.test(host),'INVALID_INPUT');
    return url;
}
export function webhookRetryAfter(value, now = Date.now()) {
    if (typeof value !== 'string' || value.length > 128) return 0;
    if (/^\d+$/.test(value)) { const n = Number(value); return Number.isSafeInteger(n) ? n : 0; }
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? Math.max(0,Math.ceil((parsed-now)/1000)) : 0;
}
function aborted(signal) {
    return signal.reason ?? new DOMException('Cancelled','AbortError');
}
function within(task, signal) {
    if (signal.aborted) return Promise.reject(aborted(signal));
    return new Promise((resolve,reject) => {
        const stop = () => reject(aborted(signal)); signal.addEventListener('abort',stop,{once:true});
        Promise.resolve(task).then(resolve,reject).finally(()=>signal.removeEventListener('abort',stop));
    });
}
/** Private dependency seams permit local TLS/hostile DNS tests. Production uses
 * native HTTPS with certificate verification and no environment proxy adapter. */
export function createWebhookSender({ resolve = lookup, requestImpl = request, timeoutMs = WEBHOOK_LIMITS.timeoutMs } = {}) {
    return async function send({ url: raw, body, deliveryId, secrets, beforeSend, signal }) {
        const controller = new AbortController();
        const stop = () => controller.abort(signal.reason); signal?.addEventListener('abort',stop,{once:true});
        if (signal?.aborted) stop();
        const timer = setTimeout(()=>controller.abort(new DOMException('Webhook deadline','TimeoutError')),timeoutMs);
        try {
            const url = validateWebhookUrl(raw);
            const answers = await within(resolve(url.hostname,{all:true,verbatim:true}),controller.signal);
            if (!Array.isArray(answers) || !answers.length || !answers.every(a=>publicWebhookAddress(a.address) && Number(a.family)===isIP(a.address)))
                return {status:null,errorCategory:'destination',retryAfterSeconds:0};
            const chosen = answers[0];
            // Checks occur after DNS and immediately before actual network dispatch.
            await within(Promise.resolve().then(()=>beforeSend()),controller.signal);
            if (controller.signal.aborted) throw aborted(controller.signal);
            const headers = signWebhook({deliveryId,body,secrets,timestamp:Math.floor(Date.now()/1000)});
            const result = await new Promise((done,fail)=>{
                const req = requestImpl(url,{
                    method:'POST', agent:false, family:chosen.family, servername:url.hostname,
                    rejectUnauthorized:true, signal:controller.signal,
                    lookup:(_hostname,options,callback)=>options.all ? callback(null,[chosen]) : callback(null,chosen.address,chosen.family),
                    headers:{...headers,'content-length':Buffer.byteLength(body,'utf8'),'user-agent':'Festapp-Webhooks/1'},
                },res=>{
                    const result={status:res.statusCode,errorCategory:res.statusCode>=200&&res.statusCode<300?null:'http',retryAfterSeconds:webhookRetryAfter(res.headers['retry-after'])};
                    // Acceptance is the final response's headers. Never retain or
                    // drain an unbounded receiver-controlled body or follow Location.
                    res.destroy(); done(result);
                });
                req.once('error',fail); req.end(body,'utf8');
            });
            return result;
        } catch(error) {
            const reason=controller.signal.reason;
            return {status:null,errorCategory:reason?.name==='TimeoutError'?'timeout':
                ['AUTHENTICATION_REQUIRED','FORBIDDEN','INSUFFICIENT_SCOPE'].includes(error.code)?'revoked':
                error.code==='INVALID_INPUT'?'destination':'network',retryAfterSeconds:0};
        } finally { clearTimeout(timer); signal?.removeEventListener('abort',stop); }
    };
}

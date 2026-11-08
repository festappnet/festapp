import {FORM_MEASUREMENT_SCRIPT_LIMIT} from '../../../web_client/src/components/forms/form_measurement_limits.js';
import {runtimeSource} from './runtime_source.mjs';
import {measurementOrigin, measurementManifest} from '../../../web_client/src/components/forms/form_measurement_contract.js';

const headers = {'cache-control':'no-store','referrer-policy':'no-referrer','x-content-type-options':'nosniff',
    'permissions-policy':'camera=(), microphone=(), geolocation=(), payment=()', 'cross-origin-opener-policy':'same-origin'};
const json = value => JSON.stringify(value).replace(/</g,'\\u003c').replace(/[\u2028\u2029]/g,c=>'\\u'+c.charCodeAt(0).toString(16));
const origin = value => {
    try {const u=new URL(value);return u.origin===value && !u.username && !u.password && ['https:','http:'].includes(u.protocol)?value:null;}catch{return null;}
};
export async function serveMeasurement(request, env, fetchConfig = async args => {
    if (env.FESTAPP_API_URL !== 'https://api.festapp.net' || !env.SUPABASE_SERVICE_ROLE_KEY) throw Error('backend unavailable');
    const response = await fetch(env.FESTAPP_API_URL+'/rest/v1/rpc/get_form_measurement_runtime_config',{
        method:'POST',headers:{'content-type':'application/json',apikey:env.SUPABASE_SERVICE_ROLE_KEY,
            authorization:'Bearer '+env.SUPABASE_SERVICE_ROLE_KEY},body:JSON.stringify(args),signal:AbortSignal.timeout(8000),redirect:'manual'});
    if (!response.ok) throw Error('configuration unavailable');
    return response.json();
}) {
    const url=new URL(request.url);
    const local=env.LOCAL_TEST === true && ['localhost','127.0.0.1'].includes(url.hostname);
    const fail=()=>new Response('Measurement unavailable',{status:404,headers});
    if (request.method!=='GET' || !measurementOrigin(url.origin,local)) return fail();
    if (url.pathname==='/runtime.js' && !url.search) return new Response(runtimeSource,{headers:{...headers,'content-type':'application/javascript; charset=utf-8'}});
    if (url.pathname!=='/runtime' || [...url.searchParams.keys()].some(k=>!['form','parent'].includes(k))) return fail();
    const form=url.searchParams.get('form'),parent=origin(url.searchParams.get('parent'));
    if (!/^[a-zA-Z0-9_-]{1,80}$/.test(form||'') || !parent || parent===url.origin ||
        (!local && new URL(parent).protocol!=='https:') || (!/^[1-9]\d*$/.test(String(env.ORGANIZATION_ID)) || !/^[1-9]\d*$/.test(String(env.UNIT_ID)))) return fail();
    try {
        const config=await fetchConfig({p_form_link:form,p_organization:Number(env.ORGANIZATION_ID),p_unit:Number(env.UNIT_ID),p_runtime_origin:url.origin,p_parent_origin:parent});
        if (!config || config.organization!==Number(env.ORGANIZATION_ID) || config.unit!==Number(env.UNIT_ID) || config.form_link!==form ||
            config.runtime_origin!==url.origin || config.parent_origin!==parent || config.profile!=='gtm-v1' ||
            config.policy?.eligible!==true || config.policy.runtime_supported!==true ||
            !Array.isArray(config.ancestor_origins) || !config.ancestor_origins.includes(parent) || config.ancestor_origins.length>32 ||
            !Array.isArray(config.collector_origins) || config.collector_origins.length>16 ||
            (config.gtm_container && !/^GTM-[A-Z0-9]{4,32}$/.test(config.gtm_container)) ||
            (config.scripts && (typeof config.scripts!=='string' || [...config.scripts].length>FORM_MEASUREMENT_SCRIPT_LIMIT))) return fail();
        // Approved destinations cannot include the app or backend. No arbitrary
        // callback/backend URL is ever accepted from request query parameters.
        const collectors=config.collector_origins.map(value=>origin(value));
        if (collectors.some(value=>!value || new URL(value).protocol!=='https:' || [parent,url.origin,'https://api.festapp.net'].includes(value))) return fail();
        const ancestors=config.ancestor_origins.map(value=>origin(value));
        if (ancestors.some(value=>!value || (!local && new URL(value).protocol!=='https:'))) return fail();
        const sources=['https://www.googletagmanager.com',...collectors].join(' ');
        const csp=`default-src 'none'; script-src 'self' 'unsafe-inline' ${sources}; script-src-attr 'none'; connect-src ${sources}; img-src ${sources}; style-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors ${ancestors.join(' ')}`;
        // Explicit fields only: never serialize the service credential or env.
        const manifest=measurementManifest(config.policy,form);
        if(!manifest || manifest.organization!==config.organization || manifest.unit!==config.unit)return fail();
        const boot={manifest,organization:config.organization,unit:config.unit,form_id:config.form_id,form_link:form,parent_origin:parent,
            gtm_container:config.gtm_container||null,scripts:config.scripts||null};
        const html=`<!doctype html><meta charset="utf-8"><title>Festapp measurement</title><script type="application/json" id="measurement-config">${json(boot)}</script><script src="/runtime.js"></script>`;
        return new Response(html,{headers:{...headers,'content-type':'text/html; charset=utf-8','content-security-policy':csp}});
    } catch {return fail();} // Do not disclose backend errors, scripts or secrets.
}
export default {fetch(request, env) { return serveMeasurement(request, env); }};

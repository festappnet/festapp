import {createHash} from 'node:crypto';
import {createInterface} from 'node:readline';
import {pathToFileURL} from 'node:url';
import {mutationInventory} from './canonical_mutation_contraction.mjs';

const legacy=new Set(mutationInventory.legacyFunctions.map(f=>f.signature.split('(')[0]));
const tables=new Set([...mutationInventory.tables,...mutationInventory.sharedTables].map(t=>t.split('.').at(-1)));
const safePath=value=>typeof value==='string' && /^\/[a-zA-Z0-9_/.-]{1,180}$/.test(value)?value:'unidentified';
const safeBuild=value=>typeof value==='string' && /^[0-9]{1,10}$/.test(value)?value:null;
const safeVersion=value=>typeof value==='string' && /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/.test(value)?value:null;
const safePlatform=value=>['web','pwa','android','ios','js','service','edge','import','cron'].includes(value)?value:null;
const uuid=value=>typeof value==='string' && /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);

// Retained logs stay inside the protected runtime/archive pipeline. Export only
// aggregates, hashed actor identity and the bounded fields below. No raw log line
// is ever returned, including when JSON/CSV is malformed.
export class MutationObservationSummary {
  requests=new Map(); routes=new Map(); scopes=new Map();
  gatewayLegacyAttempts=0; gatewayLegacySuccesses=0; gatewayRequests=0;
  firstGatewayEpoch=null; lastGatewayEpoch=null; auditRecords=0;
  unidentifiableWrites=0; rejectedObservationRecords=0;
  consume(line) {
    const marker='FESTAPP_MUTATION_OBSERVATION ';
    if(line.includes(marker)) {
      let value;
      try {value=JSON.parse(line.slice(line.indexOf(marker)+marker.length));}
      catch {this.rejectedObservationRecords++;return;}
      if(value.schemaVersion!==1 || !uuid(value.requestId) || !Number.isSafeInteger(value.pid)) {
        this.rejectedObservationRecords++;return;
      }
      if(value.event==='scope') {
        if(!Number.isSafeInteger(value.occasion) || value.occasion<=0) {this.rejectedObservationRecords++;return;}
        const key=`${value.requestId}/${value.occasion}`;
        this.scopes.set(key,{requestId:value.requestId,occasion:value.occasion});
      } else if(value.event==='request' && ['POST','PATCH','PUT','DELETE'].includes(value.method)) {
        const actor=uuid(value.actor)?createHash('sha256').update(value.actor.toLowerCase()).digest('hex'):null;
        const request={requestId:value.requestId,pid:value.pid,actorSha256:actor,
          role:['anon','authenticated','service_role'].includes(value.role)?value.role:'unidentified',
          method:value.method,path:safePath(value.path),declaredBuild:safeBuild(value.declaredBuild),
          declaredVersion:safeVersion(value.declaredVersion),declaredPlatform:safePlatform(value.declaredPlatform)};
        this.requests.set(value.requestId,request);
        if(!request.declaredBuild || !request.declaredVersion || !request.declaredPlatform || request.path==='unidentified')this.unidentifiableWrites++;
      } else this.rejectedObservationRecords++;
      return;
    }
    if(line.includes('AUDIT:')) {this.auditRecords++;return;}
    let value;
    try {value=JSON.parse(line.slice(line.indexOf('{')));} catch {return;}
    if(!Number.isFinite(value.ts) || !value.request || typeof value.request.uri!=='string')return;
    this.gatewayRequests++;
    this.firstGatewayEpoch=Math.min(this.firstGatewayEpoch??value.ts,value.ts);
    this.lastGatewayEpoch=Math.max(this.lastGatewayEpoch??value.ts,value.ts);
    const path=safePath(value.request.uri.split('?')[0]);
    const name=path.split('/').at(-1),method=value.request.method;
    if(!['POST','PATCH','PUT','DELETE'].includes(method) || (!legacy.has(name) && !tables.has(name)))return;
    const status=Number.isSafeInteger(value.status)?value.status:0;
    const key=JSON.stringify({method,path,status});
    this.routes.set(key,(this.routes.get(key)??0)+1);
    if(legacy.has(name)) {
      this.gatewayLegacyAttempts++;
      if(status>=200 && status<300)this.gatewayLegacySuccesses++;
    }
  }
  result() {
    return {schemaVersion:1,scope:mutationInventory.scope,measurementOnly:true,
      // Request counts cannot establish absence of internal/service DML, retained
      // interval continuity, force-upgrade, or supported idle/offline policy.
      g3Satisfied:false,coverageComplete:false,
      gateway:{requests:this.gatewayRequests,fromEpoch:this.firstGatewayEpoch,toEpoch:this.lastGatewayEpoch,
        legacyAttempts:this.gatewayLegacyAttempts,legacySuccesses:this.gatewayLegacySuccesses,
        routes:[...this.routes].map(([key,count])=>({...JSON.parse(key),count}))},
      database:{auditRecords:this.auditRecords,unidentifiableWrites:this.unidentifiableWrites,
        rejectedObservationRecords:this.rejectedObservationRecords,
        requests:[...this.requests.values()],scopes:[...this.scopes.values()]}};
  }
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  const summary=new MutationObservationSummary();
  for await(const line of createInterface({input:process.stdin,crlfDelay:Infinity}))summary.consume(line);
  process.stdout.write(JSON.stringify(summary.result(),null,2)+'\n');
}

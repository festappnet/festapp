import type {WalletConnector,WalletSyncResult} from './contracts.ts';
/** Same explicit capability/factory pattern as PaymentRegistry. No client module paths or silent fallback. */
export class WalletRegistry {
 private readonly factories=new Map<string,()=>WalletConnector>();
 constructor(entries:readonly(readonly[string,()=>WalletConnector])[],readonly defaultId:string) {
  for(const [id,factory] of entries){
   if(!/^[a-z][a-z0-9_-]{0,31}$/.test(id)||this.factories.has(id))throw new Error('wallet_connector_registration_invalid');
   this.factories.set(id,factory);
  }
  if(!this.has(defaultId))throw new Error('wallet_connector_registration_invalid');
 }
 has(id:unknown):id is string{return typeof id==='string'&&this.factories.has(id);}
 ids():readonly string[]{return [...this.factories.keys()];}
 resolve(id:unknown):WalletConnector {
  if(!this.has(id))throw new Error('wallet_connector_unavailable');
  const connector=this.factories.get(id)!();
  if(connector.id!==id)throw new Error('wallet_connector_identity_mismatch');
  return connector;
 }
 async reconcile() {
  const results=await Promise.allSettled(this.ids().map(async id=>[id,await this.resolve(id).reconcile()] as const));
  if(results.every(result=>result.status==='rejected'))throw new Error('wallet_sync_unavailable');
  return Object.fromEntries(results.map((result,index)=>[this.ids()[index],result.status==='fulfilled'?result.value[1]:{error:'wallet_sync_unavailable'}])) as Record<string,WalletSyncResult|{error:string}>;
 }
}

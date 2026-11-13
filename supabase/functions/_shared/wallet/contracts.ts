/** Wallet providers share the canonical ticket projection, never admission rules. */
export type WalletRpc=(name:string,params?:Record<string,unknown>)=>Promise<any>;
export type WalletState='ACTIVE'|'COMPLETED'|'INACTIVE'|'EXPIRED';
export type WalletProjection={state:WalletState;ticket:any;occasion:any;branding?:any};
export type WalletIssueInput={token:string;source:string;origin:string};
export type WalletIssueResult=
 | {kind:'redirect';url:string;state:WalletState}
 | {kind:'file';bytes:Uint8Array<ArrayBuffer>;contentType:string;filename:string};
export type WalletSyncResult={synced:number;failed:number};
export interface WalletConnector {
 readonly id:string;
 readonly delivery:'redirect'|'file';
 issue(input:WalletIssueInput):Promise<WalletIssueResult|null>;
 reconcile(limit?:number):Promise<WalletSyncResult>;
}

import {readdir,readFile,lstat} from 'node:fs/promises';
import {join} from 'node:path';
import {FileIntentStore} from '../operations/intent-store.mjs';
import {pendingIntentSchema} from '../operations/layout-contract.mjs';
import {remoteContexts} from './config.mjs';
import {check} from '../errors.mjs';

// Offline forward migration, never a request-time fallback or a second writer.
// openRemoteStorage's exclusive runtime lock must already be held by the caller.
export async function migrateLayoutIntents(config,storage) {
    const store=new FileIntentStore(storage.root),profiles=remoteContexts(config).map(c=>c.profile);
    const bindings=new Map(profiles.map(profile=>[profile.binding,profile])),actors=new Map();
    for(const grant of storage.values('Delegation')) {
        const profile=profiles.find(p=>p.binding===grant.profileBinding)??(!config.contexts&&!grant.profileBinding?config.profile:null);
        if(profile&&grant.binding){bindings.set(grant.binding,profile);actors.set(grant.binding,grant.userId);}
    }
    let files;
    try { files=await readdir(join(storage.root,'pending-layouts')); }
    catch(error){if(error.code==='ENOENT')return{inspected:0,migrated:0};throw error;}
    check(files.length<=20000,'PENDING_RECOVERY_REQUIRED');
    const intents=[];
    // Validate every source and mapping before moving any durable command.
    for(const name of files.filter(name=>/^[a-f0-9]{64}\.json$/.test(name))) {
        const path=join(storage.root,'pending-layouts',name),stat=await lstat(path);
        check(stat.isFile()&&!stat.isSymbolicLink()&&stat.size<=100000&&!(stat.mode&0o077),'PENDING_RECOVERY_REQUIRED');
        const parsed=pendingIntentSchema.safeParse(JSON.parse(await readFile(path,'utf8')));
        check(parsed.success,'PENDING_RECOVERY_REQUIRED');
        const intent=parsed.data,profile=bindings.get(intent.profileBinding);
        check(profile&&(!actors.has(intent.profileBinding)||actors.get(intent.profileBinding)===intent.userId),'PENDING_RECOVERY_REQUIRED');
        const previous={...profile,binding:intent.profileBinding};
        check(await store.path(previous,intent.userId,intent.request.occasionId)===path,'PENDING_RECOVERY_REQUIRED');
        await store.read(previous,intent.userId,intent.request.occasionId);
        intents.push({previous,profile,intent});
    }
    let migrated=0;
    for(const {previous,profile,intent} of intents) {
        if(previous.binding===profile.binding)continue;
        await store.rebind(previous,profile,intent.userId,intent.request.occasionId);migrated++;
    }
    return {inspected:intents.length,migrated};
}

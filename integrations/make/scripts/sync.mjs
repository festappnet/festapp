import { readFile } from 'node:fs/promises';
import { loadToken, createSdk, evidenceWriter, evidenceDirectory, sha256, cleanSourceRevision, safeFailure } from './lib/make-sdk.mjs';
import assert from 'node:assert/strict';

assert(process.argv.includes('--apply'), 'Use --apply to sync the existing PRIVATE app. This command never publishes or requests review.');
const root = new URL('../', import.meta.url);
const read = async p => JSON.parse(await readFile(new URL(p, root), 'utf8'));
const app = await read('app.json'), manifest = await read('src/generated/manifest.json');
const sourceRevision=cleanSourceRevision(root);
const {assemble,writeGenerated}=await import('./build.mjs');
await writeGenerated(await assemble(),{check:true});
assert.equal(app.zone, 'eu1.make.com');
assert.equal(app.organizationId, 9450617);
const request = createSdk(app, await loadToken());
const prefix = '/sdk/apps/' + app.name + '/' + app.version;
const existing = (await request(prefix)).app;
assert(existing && !existing.approved && (!existing.public || process.argv.includes('--review-update')),
    'Only the existing unapproved app may be edited; a published app requires --review-update. Never creates a review request.');
const org = (await request('/organizations/' + app.organizationId)).organization;
assert.equal(org.productName, 'Free'); assert.equal(org.autoPurchasingActivated, false);
const save = evidenceWriter(evidenceDirectory(), 'sync', {sourceRevision,app:app.name,version:app.version,generatedManifestSha256:sha256(await readFile(new URL('src/generated/manifest.json',root))),freeze:'review-freeze-20261028.json'});
try {
await request(prefix + '/base', 'PUT', await read('src/generated/base.json'));
await request(prefix + '/groups', 'PUT', await read('src/generated/groups.json'));
for (const section of ['common','api','parameters','scope','scopes'])
    await request('/sdk/apps/connections/' + app.connectionName + '/' + section, 'PUT', await read('src/generated/connections/' + section + '.json'));
for (const [kind, keys, identity] of [['rpcs',manifest.rpcs,'rpc'],['modules',manifest.modules,'module']]) {
    const inventory = await request(prefix + '/' + kind);
    const list = inventory[kind === 'rpcs' ? 'appRpcs' : 'appModules'] ?? inventory[kind] ?? [];
    const names = new Set(list.map(x => x.name));
    assert([...names].every(name => keys.includes(name)), 'Unexpected component found; inspect rather than hiding or deleting it.');
    for (const key of keys) {
        const path = 'src/generated/' + kind + '/' + key + '/';
        if (!names.has(key)) await request(prefix + '/' + kind, 'POST', await read(path + identity + '.json'));
        else if (kind === 'modules') {
            const meta=await read(path + identity + '.json');
            await request(prefix + '/modules/' + key, 'PATCH', {label:meta.label,description:meta.description,...(meta.crud?{crud:meta.crud}:{})});
        }
        else await request(prefix + '/rpcs/' + key, 'PATCH', {label:(await read(path + identity + '.json')).label});
        const sections = kind === 'modules' ? ['api','expect','interface','scope','samples'] : ['api','parameters'];
        for (const section of sections) await request(prefix + '/' + kind + '/' + key + '/' + section, 'PUT', await read(path + section + '.json'));
    }
}
process.stdout.write('Synced five modules, groups, one RPC and one OAuth connection to the existing unapproved app; no Publish or new review request.\n');

await save({status:'applied',published:false,reviewRequested:false,reviewStateBefore:{approved:existing.approved,public:existing.public,inReview:existing.inReview??null}});
} catch(error) { await save({status:'failed_or_partial',error:safeFailure(error)}); throw error; }

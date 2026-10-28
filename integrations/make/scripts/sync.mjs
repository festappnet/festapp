import { readFile, lstat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';

assert(process.argv.includes('--apply'), 'Use --apply to sync the existing PRIVATE app. This command never publishes or requests review.');
const root = new URL('../', import.meta.url);
const read = async p => JSON.parse(await readFile(new URL(p, root), 'utf8'));
const app = await read('app.json'), manifest = await read('src/generated/manifest.json');
assert.equal(app.zone, 'eu1.make.com');
assert.equal(app.organizationId, 9450617);
const tokenFile = join(homedir(), '.config/festapp/make-api-token');
const stat = await lstat(tokenFile);
assert(stat.isFile() && !stat.isSymbolicLink() && !(stat.mode & 0o077), 'Protected API token file required.');
const token = (await readFile(tokenFile, 'utf8')).trim();
const request = async (path, method = 'GET', body) => {
    const r = await fetch('https://' + app.zone + '/api/v2' + path, { method,
        headers: { authorization: 'Token ' + token, 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    if (!r.ok) {
        let error; try { error = JSON.parse(text); } catch { error = {}; }
        throw new Error(method + ' ' + path + ': HTTP ' + r.status + ' ' + (error.code ?? '') + ' ' + (error.detail ?? error.message ?? 'Request failed'));
    }
    try { return JSON.parse(text); } catch { return text; }
};
const prefix = '/sdk/apps/' + app.name + '/' + app.version;
const existing = (await request(prefix)).app;
assert(existing && !existing.public && !existing.approved, 'This sync command only edits the existing private app.');
const org = (await request('/organizations/' + app.organizationId)).organization;
assert.equal(org.productName, 'Free'); assert.equal(org.autoPurchasingActivated, false);
await request(prefix + '/base', 'PUT', await read('src/generated/base.json'));
for (const section of ['api','parameters','scope','scopes'])
    await request('/sdk/apps/connections/' + app.connectionName + '/' + section, 'PUT', await read('src/generated/connections/' + section + '.json'));
for (const [kind, keys, identity] of [['rpcs',manifest.rpcs,'rpc'],['modules',manifest.modules,'module']]) {
    const inventory = await request(prefix + '/' + kind);
    const list = inventory[kind === 'rpcs' ? 'appRpcs' : 'appModules'] ?? inventory[kind] ?? [];
    const names = new Set(list.map(x => x.name));
    assert([...names].every(name => keys.includes(name)), 'Unexpected component found; inspect rather than hiding or deleting it.');
    for (const key of keys) {
        const path = 'src/generated/' + kind + '/' + key + '/';
        if (!names.has(key)) await request(prefix + '/' + kind, 'POST', await read(path + identity + '.json'));
        const sections = kind === 'modules' ? ['api','expect','interface','scope','samples'] : ['api','parameters'];
        for (const section of sections) await request(prefix + '/' + kind + '/' + key + '/' + section, 'PUT', await read(path + section + '.json'));
    }
}
process.stdout.write('Synced five modules, one RPC and one OAuth connection to the existing private app; no Publish or review request.\n');

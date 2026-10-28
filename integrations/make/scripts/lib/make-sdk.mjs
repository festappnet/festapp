import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { open, mkdir, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
import assert from 'node:assert/strict';

export async function loadToken(path = join(homedir(), '.config/festapp/make-api-token')) {
    const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    try {
        const stat = await file.stat();
        assert(stat.isFile() && !(stat.mode & 0o077), 'Protected regular API token file required');
        const token = (await file.readFile('utf8')).trim();
        assert(token && !/\s/.test(token), 'Invalid API token file');
        return token;
    } finally { await file.close(); }
}
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export function createSdk(app, token, { fetchImpl = fetch, paceMs = 2200, timeoutMs = 30000, sleep = ms => new Promise(r => setTimeout(r, ms)) } = {}) {
    assert.equal(app.zone, 'eu1.make.com');
    assert.equal(app.name, 'vstupenky-online-buoz5u');
    assert.equal(app.connectionName, app.name);
    assert.equal(app.version, 1);
    assert.equal(app.organizationId, 9450617);
    assert.equal(app.teamId, 3387186);
    let lastRequest = 0, queue = Promise.resolve();
    return (path, method = 'GET', body, { binary = false } = {}) => {
        assert(path.startsWith('/') && !path.startsWith('//') && !/[\r\n#\\]/.test(path), 'Relative SDK path required');
        const task = queue.then(async () => {
            await sleep(Math.max(0, lastRequest + paceMs - Date.now())); lastRequest = Date.now();
            let response;
            try {
                response = await fetchImpl('https://eu1.make.com/api/v2' + path, {
                    method, redirect: 'error', signal: AbortSignal.timeout(timeoutMs),
                    headers: { authorization: 'Token ' + token, 'content-type': 'application/json' },
                    body: body === undefined ? undefined : JSON.stringify(body),
                });
            } catch { throw new Error('Make SDK '+method+' transport failed; outcome unknown for mutations'); }
            assert(response.ok, 'Make SDK '+method+' HTTP '+response.status);
            if (binary) return Buffer.from(await response.arrayBuffer());
            try { return await response.json(); } catch { throw new Error('Make SDK invalid JSON response'); }
        });
        queue = task.catch(() => {});
        return task; // No implicit retries, especially after uncertain mutation outcomes.
    };
}

// Every checkpoint has its own exclusive filename. Historical receipts and
// previous checkpoints can never be overwritten, even after a failed run.
export function evidenceWriter(directory, kind, context = {}) {
    assert(/^[a-z-]+$/.test(kind));
    const runId = new Date().toISOString().replace(/[:.]/g, '-') + '-' + randomUUID();
    let checkpoint = 0;
    return async receipt => {
        await mkdir(directory, { recursive: true });
        const name = `${kind}-${runId}-${++checkpoint}.json`;
        await writeFile(new URL(name, directory), JSON.stringify({ ...context, ...receipt, runId }, null, 2)+'\n', { flag: 'wx', mode: 0o600 });
        return name;
    };
}

export async function runInactiveScenario(request, id) {
    let result, failure;
    try {
        await request('/scenarios/'+id+'/start', 'POST', {});
        result = await request('/scenarios/'+id+'/run', 'POST', { responsive: true });
    } catch (error) { failure = error; }
    try { await request('/scenarios/'+id+'/stop', 'POST', {}); }
    catch (error) { failure = new AggregateError([...(failure ? [failure] : []), error], 'Scenario cleanup failed; inactive state unverified'); }
    if (failure) throw failure;
    return result;
}

export function cleanSourceRevision(root) {
    const cwd = fileURLToPath(root);
    assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd,encoding:'utf8'}).trim(), '', 'A clean isolated source revision is required');
    return execFileSync('git', ['rev-parse', 'HEAD'], {cwd,encoding:'utf8'}).trim();
}
export const safeFailure = error => ({name: error instanceof AggregateError ? 'AggregateError' : 'Error',
    message: /^Make SDK /.test(error.message) ? error.message : 'Gate failed; inspect the local command output',
    ...(error instanceof AggregateError ? {causes:error.errors.map(safeFailure)} : {})});

export const evidenceDirectory = () => pathToFileURL((process.env.FESTAPP_MAKE_EVIDENCE_DIRECTORY ?? join(homedir(), '.festapp/make-runs')) + '/');

export async function assertReviewerContext(request, app, context) {
    const org = (await request('/organizations/'+app.organizationId)).organization;
    assert.equal(org.productName, 'Free'); assert.equal(org.autoPurchasingActivated, false);
    const connection = (await request('/connections/'+context.connectionId)).connection;
    assert.equal(connection.teamId, app.teamId);
    assert.equal(connection.organizationId, app.organizationId);
    assert.equal(connection.authorId, context.ownerId);
    for (const id of [context.positiveScenarioId, context.guardrailsScenarioId]) {
        const scenario = (await request('/scenarios/'+id)).scenario;
        assert.equal(scenario.teamId, app.teamId);
        assert.equal(scenario.createdByUser.id, context.ownerId);
        assert.equal(scenario.isActive, false);
        const scheduling = typeof scenario.scheduling === 'string' ? JSON.parse(scenario.scheduling) : scenario.scheduling;
        assert.equal(scheduling.type, 'on-demand');
    }
}

export async function ensureScenariosInactive(request, ids) {
    const failures = [];
    for (const id of ids) {
        try {
            const state = (await request('/scenarios/'+id)).scenario;
            if (state.isActive) await request('/scenarios/'+id+'/stop', 'POST', {});
        } catch { failures.push(id); }
    }
    let inactive = false;
    try {
        const states = await Promise.all(ids.map(id => request('/scenarios/'+id)));
        inactive = states.every(({scenario}, i) => scenario.id === ids[i] && scenario.isActive === false);
    } catch { /* Failure is recorded, never represented as success. */ }
    return { cleanupFailures: failures, bothScenariosInactive: inactive };
}

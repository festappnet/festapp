import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtemp, mkdir, copyFile, readFile, writeFile, rm, symlink} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readRuntimes, validateRuntimes} from '../lib/measurement_runtimes.mjs';
import {buildInputs, measurementBuildId} from '../lib/measurement_build.mjs';
import {verifyRuntimes, sha256} from '../verify_measurement_runtimes.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const entry = {project: 'festapp-measurement-unit-17', organization: 3, unit: 17};

test('registry accepts public scope and rejects malformed, extra and duplicate entries', async () => {
  assert.deepEqual(await readRuntimes(entry.project), [entry]);
  await assert.rejects(readRuntimes('unknown'), /Unknown/);
  for (const invalid of [null, {}, [], [null], [{...entry, extra: true}],
    [{...entry, project: 'bad/project'}], [{...entry, unit: 0}],
    [{...entry, unit: 18}], [{...entry, organization: 1.5}],
    [{...entry, organization: '3'}], [{...entry, organization: Number.MAX_SAFE_INTEGER + 1}],
    [entry, entry], [entry, {...entry, organization: 4}]]) {
    assert.throws(() => validateRuntimes(invalid));
  }
});

test('public probe handles matching bytes, drift, HTTP failure, timeout and propagation retries', async () => {
  const source = 'receiver\n';
  const cases = [
    {bodies: [source], ok: true},
    {bodies: ['old', 'old', 'old'], ok: false},
    {bodies: [503, 503, 503], ok: false},
    {bodies: [null, null, null], ok: false},
    {bodies: [null, 'old', source], ok: true},
  ];
  for (const scenario of cases) {
    const calls = [], waits = [], logs = [];
    const results = await verifyRuntimes([entry], {
      expectedBuildId: 'a'.repeat(64), expectedSource: source, attempts: 3, retryMs: 7, wait: async ms => waits.push(ms), log: line => logs.push(line),
      fetchImpl: async (url, options) => {
        calls.push({url, options});
        const body = scenario.bodies[calls.length - 1];
        if (body === null) throw new DOMException('timeout', 'TimeoutError');
        return new Response(typeof body === 'number' ? '' : body, {status: typeof body === 'number' ? body : 200, headers: {'x-festapp-runtime-build': 'a'.repeat(64)}});
      },
    });
    assert.equal(results[0].ok, scenario.ok);
    assert.equal(calls.length, scenario.bodies.length);
    assert.deepEqual(waits, Array(calls.length - 1).fill(7));
    assert.equal(results[0].expected, sha256(source));
    assert.match(logs[0], scenario.ok ? / OK$/ : / DRIFT$/);
    for (const {url, options} of calls) {
      assert.equal(url, `https://${entry.project}.pages.dev/runtime.js`);
      assert.ok(options.signal instanceof AbortSignal);
      assert.equal(options.redirect, 'error');
      assert.equal(options.headers, undefined);
    }
  }
});

test('probe reports every project even when an earlier project is unavailable', async () => {
  const logs = [];
  const results = await verifyRuntimes([entry, {...entry, project: 'festapp-measurement-unit-18'}], {
    attempts: 1, fetchImpl: async () => { throw Error('unavailable'); }, log: line => logs.push(line),
  });
  assert.equal(results.length, 2);
  assert.equal(logs.length, 2);
  assert.ok(results.every(result => !result.ok && result.actual === null));
});

test('worker build is deterministic, serves the exact receiver and rejects stale generated source', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'measurement-build-'));
  try {
    const files = buildInputs;
    for (const path of files) {
      await mkdir(dirname(join(directory, path)), {recursive: true});
      await copyFile(join(root, path), join(directory, path));
    }
    await symlink(join(root, 'web_client/node_modules'), join(directory, 'web_client/node_modules'));
    const script = join(directory, 'web_client/scripts/build_measurement_worker.mjs');
    const artifact = join(directory, 'workers/form-measurement/dist/_worker.js');
    execFileSync(process.execPath, [script]);
    const first = await readFile(artifact, 'utf8');
    execFileSync(process.execPath, [script]);
    assert.equal(await readFile(artifact, 'utf8'), first);
    const {default: worker} = await import('data:text/javascript;base64,' + Buffer.from(first).toString('base64'));
    const response = await worker.fetch(new Request(`https://${entry.project}.pages.dev/runtime.js`), {});
    const {runtimeSource} = await import('../../workers/form-measurement/src/runtime_source.mjs');
    assert.equal(response.status, 200);
    const buildId = await measurementBuildId(new URL('file://' + directory + '/'));
    assert.equal(response.headers.get('x-festapp-runtime-build'), buildId);
    const missing = await worker.fetch(new Request(`https://${entry.project}.pages.dev/missing`), {});
    assert.equal(missing.status, 404);
    assert.equal(missing.headers.get('x-festapp-runtime-build'), buildId);
    await writeFile(join(directory, 'workers/form-measurement/src/worker.mjs'), (await readFile(join(directory, 'workers/form-measurement/src/worker.mjs'), 'utf8')) + '\n// changed worker\n');
    assert.notEqual(await measurementBuildId(new URL('file://' + directory + '/')), buildId);
    assert.equal(await response.text(), runtimeSource);
    await writeFile(join(directory, 'workers/form-measurement/src/runtime_source.mjs'), 'export const runtimeSource = "stale";\n');
    const failed = spawnSync(process.execPath, [script], {encoding: 'utf8'});
    assert.notEqual(failed.status, 0);
    assert.match(failed.stderr, /Measurement runtime bundle differs/);
    assert.equal(await readFile(artifact, 'utf8'), first, 'failed check preserves prior artifacts');
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('deployment dry run is offline, skips credentials, build and Wrangler', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'measurement-dry-run-'));
  try {
    await writeFile(join(directory, 'pnpm'), '#!/bin/sh\necho UNEXPECTED_WRANGLER >&2\nexit 91\n', {mode: 0o755});
    const result = spawnSync('bash', ['automation/deploy_measurement_runtimes.sh', '--dry-run', '--only', entry.project, '--branch', 'production', '--env-file', '/missing/env'], {
      cwd: root, encoding: 'utf8', env: {...process.env, PATH: `${directory}:${process.env.PATH}`},
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /branch assertion: production/);
    assert.match(result.stdout, /Verify: https:\/\/festapp-measurement-unit-17.pages.dev\/runtime.js/);
    assert.doesNotMatch(result.stderr, /UNEXPECTED/);
    const unknown = spawnSync('bash', ['automation/deploy_measurement_runtimes.sh', '--dry-run', '--only', 'unknown'], {cwd: root});
    assert.notEqual(unknown.status, 0);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('matching receiver bytes require the exact worker build identity', async () => {
  for (const header of [null, 'b'.repeat(64), 'a'.repeat(64)]) {
    const [result] = await verifyRuntimes([entry], {
      expectedSource: 'receiver', expectedBuildId: 'a'.repeat(64), attempts: 1, log() {},
      fetchImpl: async () => new Response('receiver', {headers: header ? {'x-festapp-runtime-build': header} : {}}),
    });
    assert.equal(result.ok, header === 'a'.repeat(64));
  }
});

test('deploy path binds canonical main, discovers production branches, locks, and prints rollback', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'measurement-deploy-'));
  try {
    for (const path of ['automation/deploy_measurement_runtimes.sh', 'automation/lib/measurement_runtimes.mjs', 'automation/lib/measurement_env.mjs', 'automation/lib/measurement_project.mjs']) {
      await mkdir(dirname(join(directory, path)), {recursive: true});
      await copyFile(join(root, path), join(directory, path));
    }
    await mkdir(join(directory, 'workers/form-measurement'), {recursive: true});
    await mkdir(join(directory, '.git'));
    await mkdir(join(directory, 'bin'));
    const second = {...entry, project: 'festapp-measurement-unit-18', unit: 18};
    await writeFile(join(directory, 'workers/form-measurement/runtimes.json'), JSON.stringify([entry, second]));
    const executable = async (name, body) => writeFile(join(directory, 'bin', name), '#!/bin/bash\nset -eu\n' + body, {mode: 0o755});
    await executable('git', `case "$*" in
      'rev-parse --git-common-dir') echo .git;;
      'branch --show-current') echo "\${FIX_BRANCH-main}";;
      'status --porcelain --untracked-files=normal') echo -n "\${FIX_DIRTY-}";;
      'fetch origin main') echo fetch >> calls;;
      'rev-parse HEAD') printf '%040d\\n' 1;;
      'rev-parse refs/remotes/origin/main') printf '%040d\\n' "\${FIX_REMOTE-1}";;
      *) exit 98;; esac\n`);
    await executable('python3', '[[ "$*" = "automation/ci/release_gate.py --source-sha 0000000000000000000000000000000000000001" ]]\necho gate >> calls\n');
    await executable('node', `case "$1" in
      web_client/scripts/build_measurement_worker.mjs) echo build >> calls;;
      automation/verify_measurement_runtimes.mjs) echo "verify $*" >> calls; exit "\${FIX_VERIFY-0}";;
      *) exec '${process.execPath}' "$@";; esac\n`);
    await executable('pnpm', '[[ "$1" = dlx && "$2" = wrangler@4.159.0 ]]\nshift 2\nexec wrangler "$@"\n');
    await executable('wrangler', `echo "$*" >> calls
      case "$*" in
        'pages project list --json') if [ \"\${FIX_NO_BRANCH-0}\" = 1 ]; then echo '[{\"Project Name\":\"${entry.project}\"}]'; exit 0; fi; echo '[{"Project Name":"${entry.project}","Production Branch":"production"},{"Project Name":"${second.project}","production_branch":"release"}]';;
        'pages deployment list '*) echo history >> calls; if [ \"\${FIX_EMPTY_HISTORY-0}\" = 1 ]; then echo '[]'; else echo '[{"Id":"newest-inactive-id"}]'; fi;;
        'pages deploy '*) cat >/dev/null; exit \"\${FIX_UPLOAD-0}\";;
        *) exit 97;; esac\n`);
    await executable('curl', `cat >/dev/null
      echo "api \${*: -1}" >> calls
      if [[ "\${*: -1}" = */deployments/* ]]; then
        if [ "\${FIX_DEPLOYMENT_HTTP_ERROR-0}" = 1 ]; then exit 22; fi
        echo "{\\"success\\":true,\\"result\\":{\\"id\\":\\"\${FIX_DEPLOYMENT_ID-previous-production-id}\\",\\"environment\\":\\"\${FIX_DEPLOYMENT_ENV-production}\\",\\"latest_stage\\":{\\"status\\":\\"\${FIX_DEPLOYMENT_STATUS-success}\\"}}}"
      elif [ "\${FIX_FIRST-0}" = 1 ]; then
        echo '{"success":true,"result":{"production_branch":"production","canonical_deployment":null}}'
      else
        echo '{"success":true,"result":{"production_branch":"production","canonical_deployment":{"id":"previous-production-id","environment":"production","latest_stage":{"status":"success"}}}}'
      fi
`);
    const run = (extra = {}, args = []) => spawnSync('bash', ['automation/deploy_measurement_runtimes.sh', ...args], {
      cwd: directory, encoding: 'utf8', env: {...process.env, PATH: `${directory}/bin:${process.env.PATH}`, CLOUDFLARE_API_TOKEN: randomBytes(24).toString('hex'), ...extra},
    });
    for (const [env, message] of [[{FIX_BRANCH: 'prod/tenant'}, /requires branch main/], [{FIX_BRANCH: ''}, /requires branch main/], [{FIX_REMOTE: '2'}, /HEAD must equal origin\/main/], [{FIX_DIRTY: 'modified'}, /clean checkout/]]) {
      const result = run(env);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, message);
    }
    const mismatch = run({}, ['--branch', 'main']);
    assert.notEqual(mismatch.status, 0);
    assert.match(mismatch.stderr, /does not match production/);
    await writeFile(join(directory, 'calls'), '');
    const success = run();
    assert.equal(success.status, 0, success.stderr);
    const calls = await readFile(join(directory, 'calls'), 'utf8');
    assert.match(calls, /fetch/);
    assert.match(calls, /--project-name=festapp-measurement-unit-17 --branch=production --commit-hash=0000000000000000000000000000000000000001/);
    assert.match(calls, /--project-name=festapp-measurement-unit-18 --branch=release/);
    const fallback = run({FIX_NO_BRANCH: '1'}, ['--only', entry.project]);
    assert.equal(fallback.status, 0, fallback.stderr);
    const oauth = run({}, ['--wrangler-oauth']);
    assert.notEqual(oauth.status, 0);
    assert.match(oauth.stderr, /Unknown option/);
    const noToken = run({CLOUDFLARE_API_TOKEN: ''});
    assert.notEqual(noToken.status, 0);
    assert.match(noToken.stderr, /export it or use --env-file/);
    await t.test('update resolves an active deployment outside the history page', async () => {
      assert.match(calls, /api .*\/deployments\/previous-production-id/);
      assert.doesNotMatch(calls, /pages deployment list/);
      for (const extra of [{FIX_DEPLOYMENT_ID: 'different'}, {FIX_DEPLOYMENT_ENV: 'preview'},
        {FIX_DEPLOYMENT_STATUS: 'failure'}, {FIX_DEPLOYMENT_HTTP_ERROR: '1'}]) {
        await writeFile(join(directory, 'calls'), '');
        const invalid = run(extra);
        assert.notEqual(invalid.status, 0);
        assert.doesNotMatch(await readFile(join(directory, 'calls'), 'utf8'), /pages deploy /);
      }
    });
    await t.test('first deployment succeeds without rollback and failures stop later projects', async () => {
      for (const [upload, verify] of [['0', '0'], ['0', '1'], ['1', '0']]) {
        await writeFile(join(directory, 'calls'), '');
        const first = run({FIX_FIRST: '1', FIX_EMPTY_HISTORY: '1', FIX_VERIFY: verify, FIX_UPLOAD: upload});
        assert.equal(first.status, Number(upload) || Number(verify), first.stderr);
        assert.match(first.stdout, /first production deployment: rollback is unavailable/);
        const firstCalls = await readFile(join(directory, 'calls'), 'utf8');
        assert.match(firstCalls, /pages deploy /);
        if (upload === '1' || verify === '1') {
          assert.match(first.stderr, /Keep measurement disabled/);
          assert.doesNotMatch(first.stderr, /curl|\/rollback/);
          assert.doesNotMatch(firstCalls, /--project-name=festapp-measurement-unit-18/);
        }
      }
      await writeFile(join(directory, 'calls'), '');
      const ambiguous = run({FIX_FIRST: '1'});
      assert.notEqual(ambiguous.status, 0);
      assert.match(ambiguous.stderr, /production history exists or is invalid/);
      assert.doesNotMatch(await readFile(join(directory, 'calls'), 'utf8'), /pages deploy /);
    });
    const failed = run({FIX_VERIFY: '1'});
    assert.notEqual(failed.status, 0);
    assert.match(failed.stderr, /curl --fail-with-body -X POST .*festapp-measurement-unit-17\/deployments\/previous-production-id\/rollback/);
    assert.match(failed.stderr, /\$CLOUDFLARE_API_TOKEN/);
    await mkdir(join(directory, '.git/measurement-runtime-deploy.lock'));
    assert.match(run().stderr, /already locked/);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('dotenv parser rejects missing and empty values, strips comments without executing input', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'measurement-env-'));
  try {
    const file = join(directory, 'input.env');
    for (const input of ['OTHER=value', 'CLOUDFLARE_API_TOKEN= # comment', 'CLOUDFLARE_API_TOKEN="" # comment']) {
      await writeFile(file, input);
      const result = spawnSync(process.execPath, ['automation/lib/measurement_env.mjs', file], {cwd: root, encoding: 'utf8'});
      assert.notEqual(result.status, 0);
      assert.equal(result.stdout, '');
      assert.match(result.stderr, /Env file/);
    }
    const value = randomBytes(16).toString('hex');
    for (const input of [`export CLOUDFLARE_API_TOKEN=${value} # comment`, `CLOUDFLARE_API_TOKEN="${value}" # comment`, `CLOUDFLARE_API_TOKEN='${value}' # comment`]) {
      await writeFile(file, input);
      const result = spawnSync(process.execPath, ['automation/lib/measurement_env.mjs', file], {cwd: root, encoding: 'utf8'});
      assert.equal(result.status, 0);
      assert.ok(result.stdout === value);
    }
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('project metadata projection keeps only public fields and hides malformed input', () => {
  const hidden = randomBytes(24).toString('hex');
  for (const input of [JSON.stringify({success: true, result: {production_branch: 'production',
    env_vars: {private: {value: hidden}}, canonical_deployment: {id: 'active', environment: 'production',
      env_vars: {private: {value: hidden}}, latest_stage: {status: 'success'}}}}), hidden]) {
    const result = spawnSync(process.execPath, ['automation/lib/measurement_project.mjs'], {cwd: root, input, encoding: 'utf8'});
    assert.ok(!result.stdout.includes(hidden) && !result.stderr.includes(hidden));
    if (input.startsWith('{')) {
      assert.equal(result.status, 0);
      assert.equal(JSON.parse(result.stdout).result.canonical_deployment.id, 'active');
    } else {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /metadata unavailable/);
    }
  }
});
